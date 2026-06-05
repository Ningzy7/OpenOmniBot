import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/deep_thinking_card.dart';
import 'package:ui/features/home/pages/chat/chat_page_models.dart';
import 'package:ui/features/home/pages/chat/widgets/chat_widgets.dart';
import 'package:ui/l10n/generated/app_localizations.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/widgets/agent_avatar.dart';
import 'package:ui/widgets/streaming_text.dart';

void main() {
  testWidgets('empty chat state offsets with bottom overlay inset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildLocalizedApp(
        child: ChatMessageList(
          messages: const [],
          scrollController: ScrollController(),
          bottomOverlayInset: 128,
          onBeforeTaskExecute: () async {},
        ),
      ),
    );

    await tester.pump();

    final animatedPadding = tester.widget<AnimatedPadding>(
      find.byType(AnimatedPadding),
    );

    expect(animatedPadding.padding, const EdgeInsets.only(bottom: 128));
    expect(find.text('有什么可以帮助你的？'), findsOneWidget);
  });

  testWidgets(
    'parent handoff keeps list away from latest on follow-up frames',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildMessagesWithThinkingCard();

      await tester.pumpWidget(
        _buildChatMessageListHarness(
          controller: controller,
          messages: messages,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      final deepThinkingCard = find.descendant(
        of: find.byType(ChatMessageList),
        matching: find.byType(DeepThinkingCard),
      );
      expect(deepThinkingCard, findsOneWidget);

      await tester.tap(
        find.descendant(of: deepThinkingCard, matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();

      final dragStart =
          tester.getTopLeft(deepThinkingCard) + const Offset(120, 96);
      await tester.dragFrom(dragStart, const Offset(0, 60));
      await tester.pump();

      final movedOffset = controller.offset;
      expect(movedOffset, lessThan(controller.position.maxScrollExtent - 48));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      expect(controller.offset, closeTo(movedOffset, 1));
    },
  );

  testWidgets('list resumes auto-follow after layout returns it to latest', (
    tester,
  ) async {
    final controller = ScrollController();
    var messages = _buildMessagesWithThinkingCard();
    late StateSetter setState;

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: StatefulBuilder(
          builder: (context, stateSetter) {
            setState = stateSetter;
            return SizedBox(
              width: 400,
              height: 520,
              child: ChatMessageList(
                messages: messages,
                scrollController: controller,
                onBeforeTaskExecute: () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deepThinkingCard = find.descendant(
      of: find.byType(ChatMessageList),
      matching: find.byType(DeepThinkingCard),
    );
    await tester.tap(
      find.descendant(of: deepThinkingCard, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    final dragStart =
        tester.getTopLeft(deepThinkingCard) + const Offset(120, 96);
    await tester.dragFrom(dragStart, const Offset(0, 60));
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(controller.position.maxScrollExtent));

    setState(() {
      messages = <ChatMessageModel>[
        messages.first,
        ...messages.skip(1).take(1),
      ];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));

    setState(() {
      messages = <ChatMessageModel>[
        ChatMessageModel.assistantMessage('新的最新消息', id: 'new-latest'),
        ...messages,
      ];
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
  });

  testWidgets(
    'small manual drag away from latest disables follow-up auto stick',
    (tester) async {
      final controller = ScrollController();
      var messages = _buildSimpleAssistantMessages(20, prefix: '初始消息');
      late StateSetter setState;

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: StatefulBuilder(
            builder: (context, stateSetter) {
              setState = stateSetter;
              return SizedBox(
                width: 400,
                height: 520,
                child: ChatMessageList(
                  messages: messages,
                  scrollController: controller,
                  onBeforeTaskExecute: () async {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      await tester.drag(find.byType(ListView), const Offset(0, 36));
      await tester.pumpAndSettle();

      final movedOffset = controller.offset;
      expect(movedOffset, lessThan(controller.position.maxScrollExtent));
      expect(
        movedOffset,
        greaterThan(controller.position.maxScrollExtent - 48),
      );

      setState(() {
        messages = <ChatMessageModel>[
          ChatMessageModel.assistantMessage('新的最新消息', id: 'new-latest'),
          ...messages,
        ];
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(movedOffset, 2),
        reason: 'A small manual drag away from latest should not snap back.',
      );
      expect(controller.offset, lessThan(controller.position.maxScrollExtent));
    },
  );

  testWidgets('latest user message no longer shows inline edit button', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = <ChatMessageModel>[
      ChatMessageModel.userMessage('最新用户消息', id: 'latest-user'),
      ChatMessageModel.assistantMessage('收到', id: 'assistant-1'),
      ChatMessageModel.userMessage('更早的用户消息', id: 'older-user'),
    ];

    await tester.pumpWidget(
      _buildChatMessageListHarness(controller: controller, messages: messages),
    );
    await tester.pumpAndSettle();

    final latestBubble = find.byKey(
      const ValueKey('user-message-bubble-latest-user'),
    );

    expect(latestBubble, findsOneWidget);
    expect(
      find.descendant(of: latestBubble, matching: find.byType(IconButton)),
      findsNothing,
    );
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('latest user message editing reuses bubble content area', (
    tester,
  ) async {
    final controller = ScrollController();
    final editingController = TextEditingController(text: '最新用户消息');
    final messages = <ChatMessageModel>[
      ChatMessageModel.userMessage('最新用户消息', id: 'latest-user'),
      ChatMessageModel.assistantMessage('收到', id: 'assistant-1'),
    ];

    addTearDown(editingController.dispose);

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: SizedBox(
          width: 400,
          height: 520,
          child: ChatMessageList(
            messages: messages,
            scrollController: controller,
            editingUserMessageId: 'latest-user',
            userMessageEditController: editingController,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(
      find.byKey(const ValueKey('user-message-bubble-latest-user')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存并发送'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets(
    'shared message scroll controller does not crash during long-message rebuilds',
    (tester) async {
      final controller = ScrollController();
      final messages = <ChatMessageModel>[
        ChatMessageModel.assistantMessage(
          List.generate(
            120,
            (index) => '超长消息第 ${index + 1} 行，用于复现多滚动位置场景。',
          ).join('\n'),
          id: 'long-message',
        ),
      ];

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: Column(
            children: [
              Expanded(
                child: ChatMessageList(
                  messages: messages,
                  scrollController: controller,
                  onBeforeTaskExecute: () async {},
                ),
              ),
              Expanded(
                child: ChatMessageList(
                  messages: messages,
                  scrollController: controller,
                  onBeforeTaskExecute: () async {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.positions.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared message scroll controller stays safe with deep thinking cards',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildMessagesWithThinkingCard();

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 960,
            child: Column(
              children: [
                Expanded(
                  child: ChatMessageList(
                    messages: messages,
                    scrollController: controller,
                    onBeforeTaskExecute: () async {},
                  ),
                ),
                Expanded(
                  child: ChatMessageList(
                    messages: messages,
                    scrollController: controller,
                    onBeforeTaskExecute: () async {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.positions.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'streaming deep thinking updates keep the message list pinned to latest',
    (tester) async {
      final controller = ScrollController();
      final messages = ObservableChatMessageList()
        ..replaceAllMessages(_buildStreamingThinkingMessages(thinkingLines: 1));

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 400,
            height: 520,
            child: ChatMessageList(
              messages: messages,
              scrollController: controller,
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      messages[0] = ChatMessageModel.cardMessage(<String, dynamic>{
        'type': 'deep_thinking',
        'thinkingContent': List.generate(
          40,
          (index) => '第 ${index + 1} 行流式思考内容，验证列表持续跟随最新位置。',
        ).join('\n'),
        'stage': 1,
        'isLoading': true,
        'isCollapsible': true,
        'taskID': 'streaming-thinking-card',
      }, id: 'streaming-thinking-card');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'observable agent text updates rebuild the visible streaming bubble',
    (tester) async {
      final controller = ScrollController();
      final messages = ObservableChatMessageList()
        ..replaceAllMessages([
          ChatMessageModel(
            id: 'agent-task-text',
            type: 1,
            user: 2,
            content: {
              'text': '第一段回复',
              'id': 'agent-task-text',
              'renderMarkdown': true,
            },
            streamMeta: const {
              'parentTaskId': 'agent-task',
              'kind': 'text_snapshot',
              'seq': 1,
              'isFinal': false,
            },
          ),
        ]);

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 400,
            height: 520,
            child: ChatMessageList(
              messages: messages,
              scrollController: controller,
              activeAgentTaskIds: const {'agent-task'},
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<StreamingText>(find.byType(StreamingText)).fullText,
        '第一段回复',
      );

      final existing = messages[0];
      final content = Map<String, dynamic>.from(existing.content ?? const {});
      content['text'] = '第一段回复\n第二段已经流式到达';
      messages[0] = existing.copyWith(
        content: content,
        streamMeta: const {
          'parentTaskId': 'agent-task',
          'kind': 'text_snapshot',
          'seq': 2,
          'isFinal': false,
        },
      );

      await tester.pump();

      expect(
        tester.widget<StreamingText>(find.byType(StreamingText)).fullText,
        '第一段回复\n第二段已经流式到达',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanding an older thinking card does not snap the list back to latest',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildToggleRegressionThinkingMessages();

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 400,
            height: 520,
            child: ChatMessageList(
              messages: messages,
              scrollController: controller,
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      final inkWells = find.byType(InkWell);
      expect(inkWells, findsNWidgets(2));

      final offsetBefore = controller.offset;
      final maxBefore = controller.position.maxScrollExtent;

      await tester.tap(inkWells.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(controller.position.maxScrollExtent, greaterThan(maxBefore + 40));
      expect(controller.offset, closeTo(offsetBefore, 8));
      expect(
        controller.offset,
        lessThan(controller.position.maxScrollExtent - 40),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('chat history no longer uses pull-to-refresh wrapper', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildSimpleAssistantMessages(24, prefix: '刷新机制移除');

    await tester.pumpWidget(
      _buildChatMessageListHarness(controller: controller, messages: messages),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('completed agent run collapses to summary and final answer', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildCompletedAgentRunMessages();

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: SizedBox(
          width: 400,
          height: 520,
          child: ChatMessageList(
            messages: messages,
            scrollController: controller,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed state is unified across all agent modes: the header reads
    // "已处理" rather than the per-tool count summary, regardless of how
    // many tool calls happened inside. The count summary only resurfaces
    // when the user expands the run.
    expect(find.text('已处理'), findsOneWidget);
    expect(find.text('已运行 1 条命令'), findsNothing);
    expect(find.text('最终回答'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-run-avatar-task-1')),
      findsOneWidget,
    );
    expect(find.text('运行 git status'), findsNothing);
    expect(find.text('详细思考过程'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-run-summary-task-1')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('agent-run-process-task-1')),
      findsOneWidget,
    );
    expect(find.byType(DeepThinkingCard), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(find.text('运行 git status'), findsOneWidget);
    expect(find.text('详细思考过程'), findsNothing);
    expect(find.byType(AgentAvatarCircle), findsOneWidget);
    expect(find.byType(AgentAvatarButton), findsNothing);
  });

  testWidgets(
    'codex agent run shows codex avatar and "已处理" label when collapsed',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildCompletedCodexAgentRunMessages();

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 400,
            height: 520,
            child: ChatMessageList(
              messages: messages,
              scrollController: controller,
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Collapsed: header reads "已处理 …" (possibly suffixed with an
      // elapsed-time string), NEVER "已探索 N 次搜索 …".
      expect(find.textContaining('已处理'), findsOneWidget);
      expect(find.text('已探索 2 次搜索'), findsNothing);
      // Codex group must surface the codex glyph instead of the default
      // user-configurable agent avatar.
      expect(
        find.byKey(const ValueKey('agent-run-codex-avatar-task-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-run-avatar-task-1')),
        findsNothing,
      );

      // Expanded: header still says "已处理 …" — and any inner tool-group
      // capsule (when consecutive tool cards group together) ALSO says
      // "已处理" instead of the previous count summary. So we expect AT
      // LEAST one widget with "已处理" (could be the outer header alone,
      // or outer + inner capsule depending on the messages).
      await tester.tap(find.byKey(const ValueKey('agent-run-summary-task-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已处理'), findsWidgets);
      expect(find.textContaining('已探索'), findsNothing);
    },
  );

  testWidgets(
    'agent run summary chevron stays glued to the right edge regardless of '
    'label length',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildCompletedAgentRunMessages();

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: SizedBox(
            width: 400,
            height: 520,
            child: ChatMessageList(
              messages: messages,
              scrollController: controller,
              onBeforeTaskExecute: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Regression for the "横线长度有问题" bug: the horizontal divider
      // must extend almost to the chevron — before the fix
      // Flexible(Text)+Expanded(line) split the remaining row 50/50, so
      // the line stopped near the middle of the row. We assert this
      // structurally by sampling the Expanded(Container(height:1)) widget
      // that draws the line and verifying it stretches across the bulk of
      // the row.
      final summaryToggle = find.byKey(
        const ValueKey('agent-run-summary-task-1'),
      );
      expect(summaryToggle, findsOneWidget);
      final toggleRect = tester.getRect(summaryToggle);
      final rowFinder = find.descendant(
        of: summaryToggle,
        matching: find.byType(Row),
      );
      expect(rowFinder, findsOneWidget);
      final rowRect = tester.getRect(rowFinder);
      // The Container(height:1) wrapped by Expanded is the divider line.
      final dividerFinder = find.descendant(
        of: rowFinder,
        matching: find.byWidgetPredicate((widget) {
          if (widget is! Container) return false;
          final constraints = widget.constraints;
          return constraints != null && constraints.maxHeight == 1.0;
        }),
      );
      expect(dividerFinder, findsOneWidget);
      final dividerRect = tester.getRect(dividerFinder);
      // The divider should fill at least 35% of the row width, regardless
      // of how short the label text is (the 50/50 split bug capped this
      // at ~50% minus padding; without the fix a short label like "已处理"
      // would leave a huge blank between the label and the divider).
      final minDividerWidth = rowRect.width * 0.35;
      expect(
        dividerRect.width,
        greaterThan(minDividerWidth),
        reason:
            'divider width=${dividerRect.width} must take at least '
            '${minDividerWidth.toStringAsFixed(1)} of row width '
            '(${rowRect.width.toStringAsFixed(1)}).',
      );
      // And it must extend close to the right edge of the row so the
      // chevron is glued to the right side. We allow up to chevron(18) +
      // gap(6) + inner padding(2) + safety(10) ≈ 36px from the rightmost
      // row pixel.
      expect(
        rowRect.right - dividerRect.right,
        lessThan(40),
        reason:
            'divider right=${dividerRect.right} must be within 40px of row '
            'right=${rowRect.right} (gap = chevron+spacer+padding).',
      );
      // Sanity: also confirm the entire summary fills the available list
      // width (proves the row width itself is not being collapsed).
      expect(
        rowRect.width,
        greaterThan(toggleRect.width * 0.8),
        reason: 'row should fill most of the toggle width',
      );
    },
  );

  testWidgets('adjacent tool calls collapse into an expandable group', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildCompletedAgentRunMessagesWithToolGroup();

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: SizedBox(
          width: 400,
          height: 520,
          child: ChatMessageList(
            messages: messages,
            scrollController: controller,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('agent-run-summary-task-1')));
    await tester.pumpAndSettle();

    // The per-tool count summary is no longer surfaced anywhere — both the
    // outer run header AND the inner tool-group capsule now read "已处理"
    // (the user asked for the expanded UI to match the collapsed UI).
    // There should be at least two "已处理" labels visible: the run header
    // and the inner tool group capsule.
    expect(find.text('已运行 1 条命令 · 已读取 1 个文件'), findsNothing);
    expect(find.textContaining('已处理'), findsWidgets);

    final toolGroupToggle = find.byKey(
      const ValueKey(
        'agent-tool-call-group-toggle-task-1-task-1-tool-1-task-1-tool-2',
      ),
    );
    expect(toolGroupToggle, findsOneWidget);
    expect(find.text('运行 git status'), findsNothing);
    expect(find.text('读取 README.md'), findsNothing);

    await tester.tap(toolGroupToggle);
    await tester.pumpAndSettle();

    expect(find.text('运行 git status'), findsOneWidget);
    expect(find.text('读取 README.md'), findsOneWidget);
  });

  testWidgets('reopening run collapses thinking details by default again', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildCompletedAgentRunMessages();

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: SizedBox(
          width: 400,
          height: 520,
          child: ChatMessageList(
            messages: messages,
            scrollController: controller,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summaryToggle = find.byKey(
      const ValueKey('agent-run-summary-task-1'),
    );
    await tester.tap(summaryToggle);
    await tester.pumpAndSettle();

    final thinkingToggle = find.descendant(
      of: find.byType(DeepThinkingCard),
      matching: find.byType(InkWell),
    );
    expect(thinkingToggle, findsOneWidget);

    await tester.tap(thinkingToggle);
    await tester.pumpAndSettle();
    expect(find.text('详细思考过程'), findsOneWidget);

    await tester.tap(summaryToggle);
    await tester.pumpAndSettle();
    expect(find.text('详细思考过程'), findsNothing);

    await tester.tap(summaryToggle);
    await tester.pumpAndSettle();
    expect(find.byType(DeepThinkingCard), findsOneWidget);
    expect(find.text('详细思考过程'), findsNothing);
  });

  testWidgets('agent run expansion can be controlled by the parent page', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildCompletedAgentRunMessages();
    Set<String> expandedTaskIds = <String>{};
    late StateSetter setState;

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: StatefulBuilder(
          builder: (context, stateSetter) {
            setState = stateSetter;
            return SizedBox(
              width: 400,
              height: 520,
              child: ChatMessageList(
                messages: messages,
                scrollController: controller,
                expandedAgentRunTaskIds: expandedTaskIds,
                onExpandedAgentRunTaskIdsChanged: (nextTaskIds) {
                  setState(() {
                    expandedTaskIds = nextTaskIds;
                  });
                },
                onBeforeTaskExecute: () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summaryToggle = find.byKey(
      const ValueKey('agent-run-summary-task-1'),
    );
    expect(find.text('运行 git status'), findsNothing);

    await tester.tap(summaryToggle);
    await tester.pumpAndSettle();
    expect(expandedTaskIds, const {'task-1'});
    expect(find.text('运行 git status'), findsOneWidget);

    await tester.tap(summaryToggle);
    await tester.pumpAndSettle();
    expect(expandedTaskIds, isEmpty);
    expect(find.text('运行 git status'), findsNothing);
  });

  testWidgets(
    'cancelled agent run auto-collapses trace and shows cancel body',
    (tester) async {
      final controller = ScrollController();
      final messages = ObservableChatMessageList()
        ..replaceAllMessages(_buildCompletedAgentRunMessages());
      Set<String> expandedTaskIds = <String>{'task-1'};
      late StateSetter setState;

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: StatefulBuilder(
            builder: (context, stateSetter) {
              setState = stateSetter;
              return SizedBox(
                width: 400,
                height: 520,
                child: ChatMessageList(
                  messages: messages,
                  scrollController: controller,
                  expandedAgentRunTaskIds: expandedTaskIds,
                  onExpandedAgentRunTaskIdsChanged: (nextTaskIds) {
                    setState(() {
                      expandedTaskIds = nextTaskIds;
                    });
                  },
                  onBeforeTaskExecute: () async {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('运行 git status'), findsOneWidget);

      messages.insert(
        0,
        ChatMessageModel(
          id: 'task-1-cancelled',
          type: 1,
          user: 2,
          content: const <String, dynamic>{
            'text': '任务已取消',
            'id': 'task-1-cancelled',
            'renderMarkdown': false,
          },
          streamMeta: const <String, dynamic>{
            'parentTaskId': 'task-1',
            'kind': 'text_snapshot',
            'seq': 1000000000,
            'entryId': 'task-1-cancelled',
            'isFinal': true,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(expandedTaskIds, isEmpty);
      expect(find.text('任务已取消'), findsOneWidget);
      expect(find.text('运行 git status'), findsNothing);
    },
  );

  testWidgets(
    'expanding latest agent run keeps the summary row anchored while inset grows',
    (tester) async {
      final controller = ScrollController();
      final messages = _buildCompletedAgentRunMessages();
      Set<String> expandedTaskIds = <String>{};
      late StateSetter setState;

      await tester.pumpWidget(
        _buildLocalizedApp(
          child: StatefulBuilder(
            builder: (context, stateSetter) {
              setState = stateSetter;
              return SizedBox(
                width: 400,
                height: 220,
                child: ChatMessageList(
                  messages: messages,
                  scrollController: controller,
                  expandedAgentRunTaskIds: expandedTaskIds,
                  onExpandedAgentRunTaskIdsChanged: (nextTaskIds) {
                    setState(() {
                      expandedTaskIds = nextTaskIds;
                    });
                  },
                  bottomOverlayInset: expandedTaskIds.isEmpty ? 0 : 96,
                  onBeforeTaskExecute: () async {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.offset,
        closeTo(controller.position.maxScrollExtent, 1),
      );

      final summaryToggle = find.byKey(
        const ValueKey('agent-run-summary-task-1'),
      );
      final initialTop = tester.getTopLeft(summaryToggle).dy;
      final initialOffset = controller.offset;

      await tester.tap(summaryToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final midAnimationTop = tester.getTopLeft(summaryToggle).dy;
      expect(midAnimationTop, closeTo(initialTop, 4));
      expect(controller.offset, closeTo(initialOffset, 4));
      expect(
        controller.offset,
        lessThan(controller.position.maxScrollExtent - 24),
      );
    },
  );

  testWidgets('active agent run remains expanded while task is in flight', (
    tester,
  ) async {
    final controller = ScrollController();
    final messages = _buildActiveAgentRunMessages();

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: SizedBox(
          width: 400,
          height: 520,
          child: ChatMessageList(
            messages: messages,
            activeAgentTaskIds: const <String>{'task-1'},
            scrollController: controller,
            onBeforeTaskExecute: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(find.text('已折叠运行过程'), findsNothing);
    expect(find.text('详细思考过程'), findsOneWidget);
    expect(find.text('运行 git status'), findsOneWidget);
    expect(find.text('最终回答'), findsOneWidget);
  });

  testWidgets('reaching top auto-loads older messages without jumping to top', (
    tester,
  ) async {
    final controller = ScrollController();
    var messages = _buildSimpleAssistantMessages(20, prefix: '初始消息');
    var loadMoreCalls = 0;
    late StateSetter setState;

    await tester.pumpWidget(
      _buildLocalizedApp(
        child: StatefulBuilder(
          builder: (context, stateSetter) {
            setState = stateSetter;
            return SizedBox(
              width: 400,
              height: 520,
              child: ChatMessageList(
                messages: messages,
                scrollController: controller,
                hasMore: loadMoreCalls == 0,
                onLoadMore: () async {
                  loadMoreCalls += 1;
                  setState(() {
                    messages = <ChatMessageModel>[
                      ...messages,
                      ..._buildSimpleAssistantMessages(
                        8,
                        prefix: '更早消息',
                        idPrefix: 'older',
                        startIndex: messages.length,
                      ),
                    ];
                  });
                },
                onBeforeTaskExecute: () async {},
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.jumpTo(24);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(loadMoreCalls, 1);
    expect(messages.length, 28);
    expect(controller.offset, greaterThan(24));
    expect(tester.takeException(), isNull);
  });
}

Widget _buildChatMessageListHarness({
  required ScrollController controller,
  required List<ChatMessageModel> messages,
}) {
  return _buildLocalizedApp(
    child: SizedBox(
      width: 400,
      height: 520,
      child: ChatMessageList(
        messages: messages,
        scrollController: controller,
        onBeforeTaskExecute: () async {},
      ),
    ),
  );
}

Widget _buildLocalizedApp({required Widget child}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

List<ChatMessageModel> _buildMessagesWithThinkingCard() {
  return [
    ChatMessageModel.cardMessage(<String, dynamic>{
      'type': 'deep_thinking',
      'thinkingContent': List.generate(
        80,
        (index) => '第 ${index + 1} 行思考内容，供消息列表滚动回归测试使用。',
      ).join('\n'),
      'stage': 4,
      'isLoading': false,
      'isCollapsible': true,
      'taskID': 'thinking-card',
    }, id: 'thinking-card'),
    ...List.generate(12, (index) {
      return ChatMessageModel.assistantMessage(
        List.generate(
          4,
          (line) => '较早消息 ${index + 1} - 第 ${line + 1} 行',
        ).join('\n'),
        id: 'older-$index',
      );
    }),
  ];
}

List<ChatMessageModel> _buildSimpleAssistantMessages(
  int count, {
  required String prefix,
  String idPrefix = 'assistant',
  int startIndex = 0,
}) {
  return List<ChatMessageModel>.generate(count, (index) {
    final resolvedIndex = startIndex + index;
    return ChatMessageModel.assistantMessage(
      List.generate(
        3,
        (line) => '$prefix ${resolvedIndex + 1} - 第 ${line + 1} 行内容，用于分页加载测试。',
      ).join('\n'),
      id: '$idPrefix-$resolvedIndex',
    );
  });
}

List<ChatMessageModel> _buildStreamingThinkingMessages({
  required int thinkingLines,
}) {
  return <ChatMessageModel>[
    ChatMessageModel.cardMessage(<String, dynamic>{
      'type': 'deep_thinking',
      'thinkingContent': List.generate(
        thinkingLines,
        (index) => '第 ${index + 1} 行流式思考内容，验证列表持续跟随最新位置。',
      ).join('\n'),
      'stage': 1,
      'isLoading': true,
      'isCollapsible': true,
      'taskID': 'streaming-thinking-card',
    }, id: 'streaming-thinking-card'),
    ...List.generate(18, (index) {
      return ChatMessageModel.assistantMessage(
        List.generate(
          5,
          (line) => '较早消息 ${index + 1} - 第 ${line + 1} 行',
        ).join('\n'),
        id: 'streaming-older-$index',
      );
    }),
  ];
}

List<ChatMessageModel> _buildToggleRegressionThinkingMessages() {
  return <ChatMessageModel>[
    ChatMessageModel.cardMessage(<String, dynamic>{
      'type': 'deep_thinking',
      'thinkingContent': List.generate(
        3,
        (index) => '最新思考卡第 ${index + 1} 行，保持可见。',
      ).join('\n'),
      'stage': 4,
      'isLoading': false,
      'isCollapsible': true,
      'taskID': 'latest-thinking-card',
    }, id: 'latest-thinking-card'),
    ChatMessageModel.cardMessage(<String, dynamic>{
      'type': 'deep_thinking',
      'thinkingContent': List.generate(
        60,
        (index) => '较早思考卡第 ${index + 1} 行，展开后高度明显增加。',
      ).join('\n'),
      'stage': 4,
      'isLoading': false,
      'isCollapsible': true,
      'taskID': 'older-thinking-card',
    }, id: 'older-thinking-card'),
    ...List.generate(6, (index) {
      return ChatMessageModel.assistantMessage(
        List.generate(
          3,
          (line) => '普通消息 ${index + 1} - 第 ${line + 1} 行',
        ).join('\n'),
        id: 'toggle-regression-$index',
      );
    }),
  ];
}

List<ChatMessageModel> _buildCompletedAgentRunMessages({bool isFinal = true}) {
  return <ChatMessageModel>[
    ChatMessageModel(
      id: 'task-1-text',
      type: 1,
      user: 2,
      content: const <String, dynamic>{'text': '最终回答', 'id': 'task-1-text'},
      streamMeta: <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'text_snapshot',
        'seq': 30,
        'entryId': 'task-1-text',
        'isFinal': isFinal,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'terminal',
        'toolTitle': '运行 git status',
        'summary': '命令执行完成',
        'terminalOutput': 'On branch main',
      },
      id: 'task-1-tool',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_completed',
        'seq': 20,
        'entryId': 'task-1-tool',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'deep_thinking',
        'thinkingContent': '详细思考过程',
        'stage': 4,
        'isLoading': false,
        'taskID': 'task-1',
        'cardId': 'task-1-thinking',
      },
      id: 'task-1-thinking',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'thinking_snapshot',
        'seq': 10,
        'entryId': 'task-1-thinking',
        'isFinal': false,
      },
    ),
    ChatMessageModel.userMessage('用户问题', id: 'task-1-user'),
  ];
}

List<ChatMessageModel> _buildCompletedAgentRunMessagesWithToolGroup() {
  return <ChatMessageModel>[
    ChatMessageModel(
      id: 'task-1-text',
      type: 1,
      user: 2,
      content: const <String, dynamic>{'text': '最终回答', 'id': 'task-1-text'},
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'text_snapshot',
        'seq': 30,
        'entryId': 'task-1-text',
        'isFinal': true,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'workspace',
        'toolTitle': '读取 README.md',
        'summary': '读取完成',
      },
      id: 'task-1-tool-2',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_completed',
        'seq': 25,
        'entryId': 'task-1-tool-2',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'status': 'success',
        'toolType': 'terminal',
        'toolTitle': '运行 git status',
        'summary': '命令执行完成',
        'terminalOutput': 'On branch main',
      },
      id: 'task-1-tool-1',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_completed',
        'seq': 20,
        'entryId': 'task-1-tool-1',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'deep_thinking',
        'thinkingContent': '详细思考过程',
        'stage': 4,
        'isLoading': false,
        'taskID': 'task-1',
        'cardId': 'task-1-thinking',
      },
      id: 'task-1-thinking',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'thinking_snapshot',
        'seq': 10,
        'entryId': 'task-1-thinking',
        'isFinal': false,
      },
    ),
    ChatMessageModel.userMessage('用户问题', id: 'task-1-user'),
  ];
}

List<ChatMessageModel> _buildCompletedCodexAgentRunMessages() {
  // Same shape as _buildCompletedAgentRunMessages but every tool card carries
  // cardData.uiStyle = 'codex_tool', so the AgentRunGroup widget classifies
  // the group as a codex run (collapsed → "已处理", avatar → codex SVG).
  return <ChatMessageModel>[
    ChatMessageModel(
      id: 'task-1-text',
      type: 1,
      user: 2,
      content: const <String, dynamic>{'text': '最终回答', 'id': 'task-1-text'},
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'text_snapshot',
        'seq': 30,
        'entryId': 'task-1-text',
        'isFinal': true,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'uiStyle': 'codex_tool',
        'status': 'success',
        'toolType': 'search',
        'toolTitle': 'rg foo',
        'summary': 'rg 完成',
      },
      id: 'task-1-tool-search-1',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_completed',
        'seq': 26,
        'entryId': 'task-1-tool-search-1',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'uiStyle': 'codex_tool',
        'status': 'success',
        'toolType': 'search',
        'toolTitle': 'rg bar',
        'summary': 'rg 完成',
      },
      id: 'task-1-tool-search-2',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_completed',
        'seq': 25,
        'entryId': 'task-1-tool-search-2',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'deep_thinking',
        'thinkingContent': 'codex 在思考',
        'stage': 4,
        'isLoading': false,
        'taskID': 'task-1',
        'cardId': 'task-1-thinking',
      },
      id: 'task-1-thinking',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'thinking_snapshot',
        'seq': 10,
        'entryId': 'task-1-thinking',
        'isFinal': false,
      },
    ),
    ChatMessageModel.userMessage('用户问题', id: 'task-1-user'),
  ];
}

List<ChatMessageModel> _buildActiveAgentRunMessages() {
  return <ChatMessageModel>[
    ChatMessageModel(
      id: 'task-1-text',
      type: 1,
      user: 2,
      content: const <String, dynamic>{'text': '最终回答', 'id': 'task-1-text'},
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'text_snapshot',
        'seq': 30,
        'entryId': 'task-1-text',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'agent_tool_summary',
        'status': 'running',
        'toolType': 'terminal',
        'toolTitle': '运行 git status',
        'summary': '命令执行中',
        'terminalOutput': 'On branch main',
      },
      id: 'task-1-tool',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'tool_progress',
        'seq': 20,
        'entryId': 'task-1-tool',
        'isFinal': false,
      },
    ),
    ChatMessageModel.cardMessage(
      <String, dynamic>{
        'type': 'deep_thinking',
        'thinkingContent': '详细思考过程',
        'stage': 1,
        'isLoading': true,
        'taskID': 'task-1',
        'cardId': 'task-1-thinking',
      },
      id: 'task-1-thinking',
      streamMeta: const <String, dynamic>{
        'parentTaskId': 'task-1',
        'kind': 'thinking_snapshot',
        'seq': 10,
        'entryId': 'task-1-thinking',
        'isFinal': false,
      },
    ),
    ChatMessageModel.userMessage('用户问题', id: 'task-1-user'),
  ];
}
