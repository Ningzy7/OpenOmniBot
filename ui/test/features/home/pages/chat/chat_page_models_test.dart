import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/models/chat_message_model.dart';

void main() {
  group(
    'ChatConversationRuntimeCoordinator.replaceConversationSnapshot '
    'preserveLiveStreamingState',
    () {
      final coordinator = ChatConversationRuntimeCoordinator.instance;

      setUp(() {
        coordinator.resetForTest();
      });

      tearDown(() {
        coordinator.resetForTest();
      });

      test(
        'when preserveLiveStreamingState=true the snapshot keeps reducer '
        'push state intact (regression: codex output mid-turn auto-collapse)',
        () {
          const conversationId = 0xC0DE;
          const mode = kChatRuntimeModeCodex;
          coordinator.ensureEphemeralRuntime(
            conversationId: conversationId,
            mode: mode,
          );
          final runtime = coordinator.runtimeFor(
            conversationId: conversationId,
            mode: mode,
          )!;
          // Simulate reducer push-driven streaming state populated by
          // _touchActiveTurn + _appendAssistantText + _appendThinking.
          runtime.isAiResponding = true;
          runtime.currentDispatchTaskId = 'turn-1';
          runtime.lastAgentTaskId = 'turn-1';
          runtime.currentAiMessages['msg-1-codex-agent'] = 'streaming text';
          runtime.currentThinkingMessages['turn-1'] = 'thinking text';
          runtime.currentThinkingStage = ThinkingStage.thinking.value;
          runtime.isDeepThinking = true;

          // Simulate the 2s polling tick deciding the thread looks idle.
          coordinator.replaceConversationSnapshot(
            conversationId: conversationId,
            mode: mode,
            messages: const <ChatMessageModel>[],
            isAiResponding: false,
            currentDispatchTaskId: null,
            currentThinkingStage: ThinkingStage.complete.value,
            preserveLiveStreamingState: true,
          );

          // None of the push-driven fields may have been clobbered: the
          // chat list reads runtime.activeAgentTaskIds and must still see
          // the active turn so the agent run group remains EXPANDED.
          expect(runtime.isAiResponding, isTrue);
          expect(runtime.currentDispatchTaskId, 'turn-1');
          expect(runtime.lastAgentTaskId, 'turn-1');
          expect(runtime.currentAiMessages['msg-1-codex-agent'], 'streaming text');
          expect(runtime.currentThinkingMessages['turn-1'], 'thinking text');
          expect(runtime.currentThinkingStage, ThinkingStage.thinking.value);
          expect(runtime.isDeepThinking, isTrue);
          expect(runtime.activeAgentTaskIds, contains('turn-1'));
        },
      );

      test(
        'when preserveLiveStreamingState=false (default) the snapshot fully '
        'overwrites runtime state (initial session load behaviour)',
        () {
          const conversationId = 0xBEEF;
          const mode = kChatRuntimeModeCodex;
          coordinator.ensureEphemeralRuntime(
            conversationId: conversationId,
            mode: mode,
          );
          final runtime = coordinator.runtimeFor(
            conversationId: conversationId,
            mode: mode,
          )!;
          runtime.isAiResponding = true;
          runtime.currentDispatchTaskId = 'stale-turn';
          runtime.currentAiMessages['old'] = 'old text';

          coordinator.replaceConversationSnapshot(
            conversationId: conversationId,
            mode: mode,
            messages: const <ChatMessageModel>[],
            isAiResponding: false,
            currentDispatchTaskId: null,
          );

          expect(runtime.isAiResponding, isFalse);
          expect(runtime.currentDispatchTaskId, isNull);
          expect(runtime.currentAiMessages, isEmpty);
          expect(runtime.activeAgentTaskIds, isEmpty);
        },
      );
    },
  );

  group('ObservableChatMessageList', () {
    late ObservableChatMessageList list;
    late int notifyCount;

    setUp(() {
      list = ObservableChatMessageList();
      notifyCount = 0;
      list.addListener(() {
        notifyCount += 1;
      });
    });

    tearDown(() {
      list.dispose();
    });

    test('insert triggers list-level notifyListeners', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      expect(notifyCount, 1);
    });

    test('operator []= triggers list-level notifyListeners', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      expect(notifyCount, 1);
      notifyCount = 0;

      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(
        notifyCount,
        1,
        reason:
            'in-place content updates must notify list listeners so that '
            'observers (chat_widgets._handleObservableMessagesChanged) can rebuild',
      );
      expect(list[0].text, 'hi there');
    });

    test('operator []= records content-kind mutation', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(list.lastMutationKind, ChatMessageListMutationKind.content);
    });

    test('per-item notifier still fires on operator []=', () {
      list.insert(0, ChatMessageModel.assistantMessage('hi', id: 'm-1'));
      var perItemNotifyCount = 0;
      ChatMessageModel? lastObserved;
      list.listenableAt(0).addListener(() {
        perItemNotifyCount += 1;
        lastObserved = list[0];
      });

      list[0] = ChatMessageModel.assistantMessage('hi there', id: 'm-1');
      expect(perItemNotifyCount, 1);
      expect(lastObserved?.text, 'hi there');
    });
  });
}
