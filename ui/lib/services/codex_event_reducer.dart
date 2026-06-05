import 'dart:convert';

import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/agent_stream_meta.dart';
import 'package:ui/services/codex_diff_parser.dart';
import 'package:ui/services/codex_tool_call_parser.dart';

class CodexReduceResult {
  const CodexReduceResult({
    required this.handled,
    this.method,
    this.threadId,
    this.turnId,
    this.requestId,
  });

  final bool handled;
  final String? method;
  final String? threadId;
  final String? turnId;
  final Object? requestId;
}

class CodexEventReducer {
  const CodexEventReducer();

  CodexReduceResult reduce({
    required ChatConversationRuntimeState runtime,
    required Map<String, dynamic> event,
  }) {
    final message = _asStringMap(event['message']) ?? event;
    final method = _resolveCodexEventMethod(event: event, message: message);
    if (method.isEmpty) {
      return const CodexReduceResult(handled: false);
    }

    final params = _eventParams(event: event, message: message, method: method);
    final threadId = _firstString([
      event['threadId'],
      params['threadId'],
      params['thread_id'],
      _asStringMap(params['thread'])?['id'],
    ]);
    final turnId = _firstString([
      event['turnId'],
      params['turnId'],
      params['turn_id'],
      _asStringMap(params['turn'])?['id'],
    ]);
    final itemId = _firstString([
      params['itemId'],
      params['item_id'],
      params['callId'],
      params['call_id'],
      _asStringMap(params['item'])?['id'],
      _asStringMap(params['item'])?['callId'],
      _asStringMap(params['item'])?['call_id'],
      params['processId'],
      params['processHandle'],
      params['id'],
    ]);
    final parentTaskId =
        _firstString([turnId, itemId, threadId]) ??
        'codex-${runtime.conversationId}';

    if (method == 'codex/event') {
      final protocolResult = _reduceCodexProtocolEvent(
        runtime: runtime,
        event: event,
        message: message,
        params: params,
        fallbackParentTaskId: parentTaskId,
        fallbackThreadId: threadId,
        fallbackTurnId: turnId,
      );
      if (protocolResult != null) {
        return protocolResult;
      }
    }

    if (method == 'turn/started') {
      _touchActiveTurn(runtime, parentTaskId);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'turn/completed' || method == 'thread/closed') {
      _completeTurn(runtime, parentTaskId);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'thread/started' || method == 'thread/status/changed') {
      final status = _statusType([
        params['status'],
        params['state'],
        _asStringMap(params['thread'])?['status'],
        _asStringMap(params['thread'])?['state'],
      ]);
      if (_statusIsActive(status)) {
        _touchActiveTurn(runtime, parentTaskId);
      } else if (method == 'thread/status/changed' &&
          _statusIsInactive(status)) {
        final taskId =
            turnId ??
            runtime.currentDispatchTaskId ??
            runtime.lastAgentTaskId ??
            parentTaskId;
        _completeTurn(
          runtime,
          taskId,
          appendCancelIfEmpty: _statusIsCancelled(status),
        );
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/started' || method == 'item/updated') {
      final item = _asStringMap(params['item']) ?? params;
      final itemType = canonicalCodexItemType(_string(item['type']));
      final startedItemId =
          _firstString([
            item['id'],
            item['callId'],
            item['call_id'],
            params['itemId'],
            params['callId'],
            params['call_id'],
            params['id'],
          ]) ??
          parentTaskId;
      _touchActiveTurn(runtime, parentTaskId);
      if (itemType == 'reasoning') {
        final thinkingEntryId = '$startedItemId-codex-thinking';
        final text =
            _extractText(item['text']) ??
            _extractText(item['summary']) ??
            _extractText(item['content']) ??
            '';
        _upsertThinkingCard(
          runtime,
          taskId: parentTaskId,
          cardId: thinkingEntryId,
          thinkingContent: text,
          isLoading: true,
          stage: ThinkingStage.thinking.value,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: parentTaskId,
            entryId: thinkingEntryId,
            kind: 'thinking_snapshot',
          ),
        );
      } else if (itemType == 'agentMessage') {
        final text = _extractText(item['text']) ?? '';
        if (text.isNotEmpty) {
          _appendAssistantText(
            runtime,
            parentTaskId: parentTaskId,
            entryId: '$startedItemId-codex-agent',
            delta: text,
            isFinal: false,
          );
        }
      } else if (isCodexToolItemType(itemType)) {
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: itemType,
          fallbackStatus: 'running',
        );
        final cardId =
            '$startedItemId-codex-${codexToolCardSuffix(toolInfo.toolType, itemType: itemType)}';
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: parentTaskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          terminalOutput: toolInfo.terminalOutput,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: parentTaskId,
            entryId: cardId,
            kind: method == 'item/updated' ? 'tool_progress' : 'tool_started',
          ),
        );
      } else if (itemType.contains('requestApproval')) {
        final cardId = '$startedItemId-codex-approval';
        _upsertCodexRequestCard(
          runtime,
          cardId: cardId,
          taskId: parentTaskId,
          requestId: params['requestId'] ?? message['id'],
          requestKind: 'approval',
          title: _approvalTitle(itemType, item),
          detail: _approvalDetail(item),
          params: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: parentTaskId,
            entryId: cardId,
            kind: 'permission_required',
          ),
        );
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: params['requestId'] ?? message['id'],
      );
    }

    if (method == 'item/agentMessage/delta') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['text']) ??
          _extractText(params['message']) ??
          '';
      if (delta.isNotEmpty) {
        final entryId = '${itemId ?? parentTaskId}-codex-agent';
        _appendAssistantText(
          runtime,
          parentTaskId: parentTaskId,
          entryId: entryId,
          delta: delta,
          isFinal: false,
        );
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (_isReasoningMethod(method)) {
      final text =
          _extractText(params['delta']) ??
          _extractText(params['text']) ??
          _extractText(params['summary']) ??
          _extractText(params['part']) ??
          '';
      if (text.isNotEmpty) {
        final entryId = '${itemId ?? parentTaskId}-codex-thinking';
        _appendThinking(
          runtime,
          parentTaskId: parentTaskId,
          cardId: entryId,
          delta: text,
        );
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/plan/delta' || method == 'turn/plan/updated') {
      final text =
          _extractText(params['delta']) ??
          _extractText(params['plan']) ??
          _extractText(params['text']) ??
          '';
      final cardId = '${itemId ?? parentTaskId}-codex-plan';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'plan',
        title: 'Codex plan',
        status: 'running',
        summary: text,
        progress: text,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_progress',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/commandExecution/outputDelta' ||
        method == 'item/commandExecution/terminalInteraction') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['output']) ??
          _extractText(params['text']) ??
          '';
      final callId = itemId ?? parentTaskId;
      final existingCardId = _findToolCardIdForCallId(runtime, callId);
      final existing = existingCardId == null
          ? null
          : _toolCardData(runtime, existingCardId);
      final cardId = existingCardId ?? '$callId-codex-command';
      final toolType = (existing?['toolType'] ?? '').toString().trim();
      final title =
          (existing?['toolTitle'] ?? existing?['displayName'])?.toString() ??
          _commandTitle(params);
      final outputTaskId =
          _firstString([existing?['taskId'], parentTaskId]) ?? parentTaskId;
      _appendToolOutput(
        runtime,
        cardId: cardId,
        taskId: outputTaskId,
        toolType: toolType.isEmpty ? 'terminal' : toolType,
        title: title,
        outputDelta: delta,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: outputTaskId,
          entryId: cardId,
          kind: 'tool_progress',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'command/exec/outputDelta' ||
        method == 'process/outputDelta') {
      final delta = _standaloneProcessOutputDelta(params);
      final standaloneId = _standaloneProcessId(params, method: method);
      final cardId = '$standaloneId-codex-command';
      _appendToolOutput(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'terminal',
        title: _standaloneCommandTitle(params, fallback: standaloneId),
        outputDelta: delta,
        raw: <String, dynamic>{
          ...params,
          'type': method == 'command/exec/outputDelta'
              ? 'commandExec'
              : 'processExecution',
        },
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_progress',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'process/exited' || method == 'command/exec/completed') {
      _completeStandaloneProcess(runtime, parentTaskId, params, method);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/fileChange/outputDelta' ||
        method == 'item/fileChange/patchUpdated' ||
        method == 'turn/diff/updated') {
      final delta =
          _extractText(params['delta']) ??
          _extractText(params['output']) ??
          _extractText(params['text']) ??
          '';
      final cardId = '${itemId ?? parentTaskId}-codex-file';
      _appendToolOutput(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'file',
        title: _fileChangeTitle(params),
        outputDelta: delta,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_progress',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method.endsWith('requestApproval')) {
      final requestId = message['id'];
      final cardId = '${requestId ?? itemId ?? parentTaskId}-codex-approval';
      _upsertCodexRequestCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        requestId: requestId,
        requestKind: 'approval',
        title: _approvalTitle(method, params),
        detail: _approvalDetail(params),
        params: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'permission_required',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: requestId,
      );
    }

    if (method == 'item/tool/requestUserInput') {
      final requestId = message['id'];
      final question = _firstQuestion(params);
      final cardId = '${requestId ?? itemId ?? parentTaskId}-codex-user-input';
      _upsertCodexRequestCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        requestId: requestId,
        requestKind: 'user_input',
        title: question.title,
        detail: question.detail,
        questionId: question.id,
        params: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'clarify_required',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: requestId,
      );
    }

    if (method == 'item/mcpToolCall/progress') {
      final progress =
          _extractText(params['message']) ??
          _extractText(params['progress']) ??
          '';
      final cardId = '${itemId ?? parentTaskId}-codex-tool';
      final existing = _toolCardData(runtime, cardId);
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: (existing?['toolType'] ?? 'mcp').toString(),
        title:
            (existing?['toolTitle'] ?? existing?['displayName'] ?? 'Codex tool')
                .toString(),
        status: 'running',
        summary: progress,
        progress: progress,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_progress',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/tool/call') {
      final toolInfo = normalizeCodexToolCall(
        <String, dynamic>{...params, 'type': 'dynamicToolCall'},
        itemType: 'dynamicToolCall',
        fallbackStatus: 'running',
      );
      final dynamicItemId =
          _firstString([params['callId'], params['itemId'], itemId]) ??
          parentTaskId;
      final cardId =
          '$dynamicItemId-codex-${codexToolCardSuffix(toolInfo.toolType, itemType: toolInfo.itemType)}';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: toolInfo.toolType,
        title: toolInfo.toolTitle,
        status: toolInfo.status,
        summary: toolInfo.summary,
        progress: toolInfo.progress,
        raw: <String, dynamic>{...params, 'type': 'dynamicToolCall'},
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_started',
        ),
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
        requestId: message['id'],
      );
    }

    if (method == 'rawResponseItem/completed') {
      _completeRawResponseItem(runtime, parentTaskId, params);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'item/completed') {
      _completeItem(runtime, parentTaskId, itemId, params);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'turn/failed') {
      final detail =
          _extractText(_asStringMap(params['error'])?['message']) ??
          _extractText(params['message']) ??
          _extractText(params['error']) ??
          _safeJson(params);
      final cardId = '$parentTaskId-codex-status';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'status',
        title: method,
        status: 'error',
        summary: detail,
        progress: detail,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'error',
          isFinal: true,
        ),
        touchTurn: false,
      );
      final completionTaskId =
          turnId ??
          runtime.currentDispatchTaskId ??
          runtime.lastAgentTaskId ??
          parentTaskId;
      _completeTurn(runtime, completionTaskId, appendCancelIfEmpty: false);
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'account/updated' ||
        method == 'account/login/completed' ||
        method == 'account/rateLimits/updated' ||
        method == 'account/read') {
      final cardId = '$parentTaskId-codex-account';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'account',
        title: method,
        status: 'success',
        summary: _accountSummary(params),
        progress: _accountSummary(params),
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'tool_completed',
          isFinal: true,
        ),
        touchTurn: false,
      );
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'codex/stderr' || method == 'codex/parseError') {
      final removedStaleCard = _removeCodexDebugStatusCards(runtime);
      return CodexReduceResult(
        handled: removedStaleCard,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    if (method == 'error') {
      final detail =
          _extractText(params['message']) ??
          _extractText(params['error']) ??
          _safeJson(params);
      final cardId = '$parentTaskId-codex-status';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: parentTaskId,
        toolType: 'status',
        title: method,
        status: 'error',
        summary: detail,
        progress: detail,
        raw: params,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: cardId,
          kind: 'error',
          isFinal: true,
        ),
        touchTurn: false,
      );
      // codex app-server emits the top-level `error` notification when a
      // turn fails terminally (network, rate-limit, server error). When
      // willRetry=false the server will NOT follow up with turn/completed,
      // so we must finalize the turn ourselves — otherwise runtime stays
      // isAiResponding=true forever.
      final willRetry = params['willRetry'] == true;
      if (!willRetry) {
        final completionTaskId =
            turnId ??
            runtime.currentDispatchTaskId ??
            runtime.lastAgentTaskId ??
            parentTaskId;
        _completeTurn(runtime, completionTaskId, appendCancelIfEmpty: false);
      }
      return CodexReduceResult(
        handled: true,
        method: method,
        threadId: threadId,
        turnId: turnId,
      );
    }

    return CodexReduceResult(
      handled: false,
      method: method,
      threadId: threadId,
      turnId: turnId,
    );
  }

  CodexReduceResult? _reduceCodexProtocolEvent({
    required ChatConversationRuntimeState runtime,
    required Map<String, dynamic> event,
    required Map<String, dynamic> message,
    required Map<String, dynamic> params,
    required String fallbackParentTaskId,
    required String? fallbackThreadId,
    required String? fallbackTurnId,
  }) {
    final msg =
        _codexProtocolMsg(params) ??
        _codexProtocolMsg(message) ??
        _codexProtocolMsg(event);
    if (msg == null) {
      return null;
    }
    final msgType = _normalizeCodexProtocolMsgType(_string(msg['type']));
    if (msgType.isEmpty) {
      return null;
    }

    final meta =
        _codexProtocolMeta(params) ??
        _codexProtocolMeta(message) ??
        _codexProtocolMeta(event);
    final protocolThreadId = _firstString([
      fallbackThreadId,
      params['threadId'],
      params['thread_id'],
      meta?['threadId'],
      meta?['thread_id'],
      msg['threadId'],
      msg['thread_id'],
      _asStringMap(msg['thread'])?['id'],
    ]);
    final protocolTurnId = _firstString([
      fallbackTurnId,
      params['turnId'],
      params['turn_id'],
      msg['turnId'],
      msg['turn_id'],
      _asStringMap(msg['turn'])?['id'],
    ]);
    final eventId = _firstString([params['id'], message['id'], event['id']]);
    final callId = _firstString([
      msg['callId'],
      msg['call_id'],
      msg['itemId'],
      msg['item_id'],
      msg['processId'],
      msg['process_id'],
      _asStringMap(msg['item'])?['id'],
      _asStringMap(msg['item'])?['callId'],
      _asStringMap(msg['item'])?['call_id'],
      eventId,
    ]);

    String taskIdFor({String? existingCardId}) {
      final existing = existingCardId == null
          ? null
          : _toolCardData(runtime, existingCardId);
      return _firstString([
            protocolTurnId,
            existing?['taskId'],
            runtime.currentDispatchTaskId,
            runtime.lastAgentTaskId,
            callId,
            protocolThreadId,
            fallbackParentTaskId,
          ]) ??
          fallbackParentTaskId;
    }

    CodexReduceResult handled({bool handled = true}) {
      return CodexReduceResult(
        handled: handled,
        method: 'codex/event/$msgType',
        threadId: protocolThreadId,
        turnId: protocolTurnId,
        requestId: meta?['requestId'] ?? meta?['request_id'],
      );
    }

    Map<String, dynamic> lifecycleParams(Map<String, dynamic> item) {
      return <String, dynamic>{
        ..._topLevelCodexIds(params),
        ..._topLevelCodexIds(msg),
        if (protocolThreadId != null) 'threadId': protocolThreadId,
        if (protocolTurnId != null) 'turnId': protocolTurnId,
        if (callId != null) 'itemId': callId,
        'item': item,
      };
    }

    switch (msgType) {
      case 'task_started':
      case 'turn_started':
        _touchActiveTurn(runtime, taskIdFor());
        return handled();
      case 'task_complete':
      case 'turn_complete':
      case 'turn_aborted':
        final lastMessage = _extractText(msg['last_agent_message']);
        final taskId = taskIdFor();
        if (lastMessage != null && lastMessage.trim().isNotEmpty) {
          _appendAssistantText(
            runtime,
            parentTaskId: taskId,
            entryId: '$taskId-codex-agent',
            delta: lastMessage,
            isFinal: true,
            replace: true,
          );
        }
        _completeTurn(
          runtime,
          taskId,
          appendCancelIfEmpty: msgType == 'turn_aborted',
        );
        return handled();
      case 'agent_message':
        final text = _extractText(msg['message'] ?? msg['text']) ?? '';
        if (text.isNotEmpty) {
          final taskId = taskIdFor();
          _appendAssistantText(
            runtime,
            parentTaskId: taskId,
            entryId: '${eventId ?? taskId}-codex-agent',
            delta: text,
            isFinal: false,
            replace: true,
          );
        }
        return handled();
      case 'agent_message_content_delta':
        final delta = _extractText(msg['delta']) ?? '';
        if (delta.isNotEmpty) {
          final itemId =
              _firstString([msg['itemId'], msg['item_id'], callId]) ??
              taskIdFor();
          final taskId = taskIdFor();
          _appendAssistantText(
            runtime,
            parentTaskId: taskId,
            entryId: '$itemId-codex-agent',
            delta: delta,
            isFinal: false,
          );
        }
        return handled();
      case 'agent_reasoning':
      case 'agent_reasoning_raw_content':
      case 'reasoning_content_delta':
      case 'reasoning_raw_content_delta':
        final text =
            _extractText(msg['delta']) ?? _extractText(msg['text']) ?? '';
        if (text.isNotEmpty) {
          final itemId =
              _firstString([msg['itemId'], msg['item_id'], callId]) ??
              taskIdFor();
          final taskId = taskIdFor();
          _appendThinking(
            runtime,
            parentTaskId: taskId,
            cardId: '$itemId-codex-thinking',
            delta: text,
          );
        }
        return handled();
      case 'plan_update':
      case 'plan_delta':
        final text =
            _extractText(msg['delta']) ??
            _extractText(msg['plan']) ??
            _safeJson(msg);
        final itemId =
            _firstString([msg['itemId'], msg['item_id'], callId]) ??
            taskIdFor();
        final taskId = taskIdFor();
        _upsertToolCard(
          runtime,
          cardId: '$itemId-codex-plan',
          taskId: taskId,
          toolType: 'plan',
          title: 'Codex plan',
          status: 'running',
          summary: text,
          progress: text,
          raw: <String, dynamic>{...msg, 'type': 'plan'},
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: '$itemId-codex-plan',
            kind: 'tool_progress',
          ),
        );
        return handled();
      case 'item_started':
        final item = _asStringMap(msg['item']);
        if (item == null) {
          return handled(handled: false);
        }
        return reduce(
          runtime: runtime,
          event: {'method': 'item/started', 'params': lifecycleParams(item)},
        );
      case 'item_completed':
        final item = _asStringMap(msg['item']);
        if (item == null) {
          return handled(handled: false);
        }
        return reduce(
          runtime: runtime,
          event: {'method': 'item/completed', 'params': lifecycleParams(item)},
        );
      case 'raw_response_item':
        final item = _asStringMap(msg['item']);
        if (item == null) {
          return handled(handled: false);
        }
        return reduce(
          runtime: runtime,
          event: {
            'method': 'rawResponseItem/completed',
            'params': lifecycleParams(item),
          },
        );
      case 'exec_command_begin':
        final item = _codexProtocolCommandItem(msg, status: 'running');
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'commandExecution',
          fallbackStatus: 'running',
        );
        final id = _firstString([item['id'], callId]) ?? taskIdFor();
        final suffix = codexToolCardSuffix(
          toolInfo.toolType,
          itemType: toolInfo.itemType,
        );
        final cardId = '$id-codex-$suffix';
        final taskId = taskIdFor(existingCardId: cardId);
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          terminalOutput: toolInfo.terminalOutput,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: 'tool_started',
          ),
        );
        return handled();
      case 'exec_command_output_delta':
      case 'terminal_interaction':
        final id = callId ?? taskIdFor();
        final existingCardId = callId == null
            ? null
            : _findToolCardIdForCallId(runtime, callId);
        final existing = existingCardId == null
            ? null
            : _toolCardData(runtime, existingCardId);
        final cardId = existingCardId ?? '$id-codex-command';
        final outputDelta = msgType == 'terminal_interaction'
            ? _streamOutputBlock(msg['stdin'], stream: 'stdin')
            : _codexProtocolOutputDelta(msg);
        final taskId = taskIdFor(existingCardId: existingCardId);
        final toolType = (existing?['toolType'] ?? '').toString().trim();
        final title =
            (existing?['toolTitle'] ?? existing?['displayName'])?.toString() ??
            _commandTitle(_codexProtocolCommandItem(msg, status: 'running'));
        _appendToolOutput(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolType.isEmpty ? 'terminal' : toolType,
          title: title,
          outputDelta: outputDelta,
          raw: _codexProtocolCommandItem(msg, status: 'running'),
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: 'tool_progress',
          ),
        );
        return handled();
      case 'exec_command_end':
        final item = _codexProtocolCommandItem(msg, status: null);
        final id = _firstString([item['id'], callId]) ?? taskIdFor();
        final existingCardId = callId == null
            ? null
            : _findToolCardIdForCallId(runtime, callId);
        final existing = existingCardId == null
            ? null
            : _toolCardData(runtime, existingCardId);
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'commandExecution',
          fallbackToolType: (existing?['toolType'] ?? '').toString(),
          fallbackTitle: (existing?['toolTitle'] ?? existing?['displayName'])
              ?.toString(),
          fallbackStatus: 'success',
        );
        final suffix = codexToolCardSuffix(
          toolInfo.toolType,
          itemType: toolInfo.itemType,
        );
        final cardId = existingCardId ?? '$id-codex-$suffix';
        final taskId = taskIdFor(existingCardId: existingCardId);
        final existingOutput = (existing?['terminalOutput'] ?? '').toString();
        final finalOutput = _codexProtocolFinalCommandOutput(msg);
        final output = finalOutput.isNotEmpty ? finalOutput : existingOutput;
        final exitCode = _asInt(msg['exitCode'] ?? msg['exit_code']);
        final summary = exitCode == null
            ? 'Command completed'
            : 'Command exited with code $exitCode';
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: summary,
          progress: summary,
          terminalOutput: output,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: 'tool_completed',
            isFinal: true,
          ),
          touchTurn: false,
        );
        runtime.codexReplayDeltaOffsets.remove(cardId);
        return handled();
      case 'mcp_tool_call_begin':
      case 'mcp_tool_call_end':
        final isEnd = msgType == 'mcp_tool_call_end';
        final item = _codexProtocolMcpToolItem(
          msg,
          status: isEnd ? null : 'running',
        );
        final id = _firstString([item['id'], callId]) ?? taskIdFor();
        final existingCardId = callId == null
            ? null
            : _findToolCardIdForCallId(runtime, callId);
        final existing = existingCardId == null
            ? null
            : _toolCardData(runtime, existingCardId);
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'mcpToolCall',
          fallbackToolType: (existing?['toolType'] ?? '').toString(),
          fallbackTitle: (existing?['toolTitle'] ?? existing?['displayName'])
              ?.toString(),
          fallbackStatus: isEnd ? 'success' : 'running',
        );
        final suffix = codexToolCardSuffix(
          toolInfo.toolType,
          itemType: toolInfo.itemType,
        );
        final cardId = existingCardId ?? '$id-codex-$suffix';
        final taskId = taskIdFor(existingCardId: existingCardId);
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          terminalOutput: toolInfo.terminalOutput,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: isEnd ? 'tool_completed' : 'tool_started',
            isFinal: isEnd,
          ),
          touchTurn: !isEnd,
        );
        if (isEnd) {
          runtime.codexReplayDeltaOffsets.remove(cardId);
        }
        return handled();
      case 'web_search_begin':
      case 'web_search_end':
        final isEnd = msgType == 'web_search_end';
        final item = _codexProtocolWebSearchItem(
          msg,
          status: isEnd ? 'completed' : 'running',
        );
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'webSearch',
          fallbackStatus: isEnd ? 'success' : 'running',
        );
        final id = _firstString([item['id'], callId]) ?? taskIdFor();
        final cardId = '$id-codex-search';
        final taskId = taskIdFor(existingCardId: cardId);
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: isEnd ? 'tool_completed' : 'tool_started',
            isFinal: isEnd,
          ),
          touchTurn: !isEnd,
        );
        return handled();
      case 'view_image_tool_call':
        final item = <String, dynamic>{
          ...msg,
          'id': callId,
          'type': 'imageView',
          'status': 'completed',
        };
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'imageView',
          fallbackStatus: 'success',
        );
        final id = callId ?? taskIdFor();
        final cardId = '$id-codex-image';
        final taskId = taskIdFor(existingCardId: cardId);
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: 'tool_completed',
            isFinal: true,
          ),
          touchTurn: false,
        );
        return handled();
      case 'patch_apply_begin':
      case 'patch_apply_updated':
      case 'patch_apply_end':
        final isEnd = msgType == 'patch_apply_end';
        final item = _codexProtocolPatchItem(
          msg,
          status: isEnd ? null : 'running',
        );
        final toolInfo = normalizeCodexToolCall(
          item,
          itemType: 'fileChange',
          fallbackStatus: isEnd ? 'success' : 'running',
        );
        final id = _firstString([item['id'], callId]) ?? taskIdFor();
        final cardId = '$id-codex-file';
        final taskId = taskIdFor(existingCardId: cardId);
        _upsertToolCard(
          runtime,
          cardId: cardId,
          taskId: taskId,
          toolType: toolInfo.toolType,
          title: toolInfo.toolTitle,
          status: toolInfo.status,
          summary: toolInfo.summary,
          progress: toolInfo.progress,
          terminalOutput: toolInfo.terminalOutput,
          raw: item,
          streamMeta: _streamMeta(
            runtime,
            parentTaskId: taskId,
            entryId: cardId,
            kind: isEnd ? 'tool_completed' : 'tool_progress',
            isFinal: isEnd,
          ),
          touchTurn: !isEnd,
        );
        return handled();
    }
    return null;
  }

  void _touchActiveTurn(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
  ) {
    runtime.isAiResponding = true;
    runtime.currentDispatchTaskId = parentTaskId;
    runtime.lastAgentTaskId = parentTaskId;
    runtime.currentThinkingStage = ThinkingStage.thinking.value;
  }

  void _appendAssistantText(
    ChatConversationRuntimeState runtime, {
    required String parentTaskId,
    required String entryId,
    required String delta,
    required bool isFinal,
    bool replace = false,
  }) {
    final messageId = entryId;
    final index = runtime.messages.indexWhere(
      (message) => message.id == messageId,
    );
    final cachedText = runtime.currentAiMessages[messageId];
    final previous =
        cachedText ?? (index == -1 ? '' : runtime.messages[index].text ?? '');
    final effectiveDelta = replace
        ? delta
        : _deduplicateReplayDelta(
            runtime,
            entryId: messageId,
            existingText: previous,
            delta: delta,
            hasLiveCache: cachedText != null,
          );
    if (effectiveDelta == null) {
      return;
    }
    _touchActiveTurn(runtime, parentTaskId);
    final next = replace ? effectiveDelta : previous + effectiveDelta;
    runtime.codexReplayDeltaOffsets.remove(messageId);
    runtime.currentAiMessages[messageId] = next;
    if (next.isEmpty && index == -1) {
      return;
    }
    final existing = index == -1 ? null : runtime.messages[index];
    final streamMeta = _streamMeta(
      runtime,
      parentTaskId: parentTaskId,
      entryId: messageId,
      kind: 'text_snapshot',
      isFinal: isFinal,
      existingMessage: existing,
    );
    final content = <String, dynamic>{'text': next, 'id': messageId};
    if (index == -1) {
      runtime.messages.insert(
        0,
        ChatMessageModel(
          id: messageId,
          type: 1,
          user: 2,
          content: content,
          streamMeta: streamMeta,
          createAt: DateTime.fromMillisecondsSinceEpoch(
            _startTimeForEntry(runtime, messageId, existingMessage: existing),
          ),
        ),
      );
      return;
    }
    runtime.messages[index] = runtime.messages[index].copyWith(
      content: content,
      isLoading: false,
      isError: false,
      streamMeta: streamMeta,
    );
  }

  void _appendThinking(
    ChatConversationRuntimeState runtime, {
    required String parentTaskId,
    required String cardId,
    required String delta,
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existingContent = index == -1
        ? ''
        : (runtime.messages[index].cardData?['thinkingContent'] ?? '')
              .toString();
    final cachedThinking = runtime.currentThinkingMessages[parentTaskId];
    final baseContent = cachedThinking ?? existingContent;
    final effectiveDelta = _deduplicateReplayDelta(
      runtime,
      entryId: cardId,
      existingText: baseContent,
      delta: delta,
      hasLiveCache: cachedThinking != null,
    );
    if (effectiveDelta == null) {
      return;
    }
    _touchActiveTurn(runtime, parentTaskId);
    runtime.isDeepThinking = true;
    runtime.currentThinkingStage = ThinkingStage.thinking.value;
    final nextContent = baseContent + effectiveDelta;
    runtime.codexReplayDeltaOffsets.remove(cardId);
    runtime.currentThinkingMessages[parentTaskId] = nextContent;
    runtime.deepThinkingContent = nextContent;
    _upsertThinkingCard(
      runtime,
      taskId: parentTaskId,
      cardId: cardId,
      thinkingContent: nextContent,
      isLoading: true,
      stage: ThinkingStage.thinking.value,
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: parentTaskId,
        entryId: cardId,
        kind: 'thinking_snapshot',
        existingMessage: index == -1 ? null : runtime.messages[index],
      ),
    );
  }

  void _upsertThinkingCard(
    ChatConversationRuntimeState runtime, {
    required String taskId,
    required String cardId,
    required String thinkingContent,
    required bool isLoading,
    required int stage,
    required Map<String, dynamic> streamMeta,
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existing = index == -1 ? null : runtime.messages[index];
    final existingCardData = existing?.cardData ?? const <String, dynamic>{};
    final startTime =
        _asInt(existingCardData['startTime']) ??
        _startTimeForEntry(runtime, cardId, existingMessage: existing);
    final endTime = isLoading
        ? existingCardData['endTime']
        : (existingCardData['endTime'] ??
              DateTime.now().millisecondsSinceEpoch);
    final cardData = <String, dynamic>{
      'type': 'deep_thinking',
      'isLoading': isLoading,
      'thinkingContent': thinkingContent.isNotEmpty
          ? thinkingContent
          : (existingCardData['thinkingContent'] ?? '').toString(),
      'stage': stage,
      'taskID': taskId,
      'cardId': cardId,
      'startTime': startTime,
      'endTime': endTime,
      'isCollapsible': !isLoading,
    };
    final message = ChatMessageModel(
      id: cardId,
      type: 2,
      user: 3,
      content: {'cardData': cardData, 'id': cardId},
      streamMeta: streamMeta,
      createAt: DateTime.fromMillisecondsSinceEpoch(startTime),
    );
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = existing!.copyWith(
        content: {'cardData': cardData, 'id': cardId},
        streamMeta: streamMeta,
      );
    }
  }

  void _appendToolOutput(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required String taskId,
    required String toolType,
    required String title,
    required String outputDelta,
    required Map<String, dynamic> raw,
    required Map<String, dynamic> streamMeta,
  }) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existingCardData = index == -1
        ? const <String, dynamic>{}
        : runtime.messages[index].cardData ?? const <String, dynamic>{};
    final existingOutput = (existingCardData['terminalOutput'] ?? '')
        .toString();
    final output = _trimTerminalOutput(existingOutput + outputDelta);
    _upsertToolCard(
      runtime,
      cardId: cardId,
      taskId: taskId,
      toolType: toolType,
      title: title,
      status: 'running',
      summary: outputDelta.isNotEmpty ? outputDelta.trim() : title,
      progress: outputDelta,
      terminalOutput: output,
      raw: raw,
      streamMeta: streamMeta,
    );
  }

  void _upsertToolCard(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required String taskId,
    required String toolType,
    required String title,
    required String status,
    required String summary,
    required String progress,
    required Map<String, dynamic> raw,
    required Map<String, dynamic> streamMeta,
    bool touchTurn = true,
    String terminalOutput = '',
  }) {
    if (touchTurn) {
      _touchActiveTurn(runtime, taskId);
    }
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existing = index == -1 ? null : runtime.messages[index];
    final existingCardData = existing?.cardData ?? const <String, dynamic>{};
    final toolInfo = normalizeCodexToolCall(
      raw,
      fallbackToolType: toolType,
      fallbackTitle: title,
      fallbackStatus: status,
    );
    final effectiveToolType = toolInfo.toolType.isNotEmpty
        ? toolInfo.toolType
        : toolType;
    final effectiveTitle = toolInfo.toolTitle.isNotEmpty
        ? toolInfo.toolTitle
        : title;
    final normalizedSummary = summary.isNotEmpty
        ? summary
        : toolInfo.summary.isNotEmpty
        ? toolInfo.summary
        : '';
    final normalizedProgress = progress.isNotEmpty
        ? progress
        : toolInfo.progress.isNotEmpty
        ? toolInfo.progress
        : '';
    final effectiveTerminalOutput = terminalOutput.isNotEmpty
        ? terminalOutput
        : toolInfo.terminalOutput.isNotEmpty
        ? toolInfo.terminalOutput
        : (existingCardData['terminalOutput'] ?? '').toString();
    final diffText = effectiveToolType == 'file'
        ? _resolveFileDiffText(
            existingCardData: existingCardData,
            raw: raw,
            terminalOutput: effectiveTerminalOutput,
            progress: normalizedProgress,
            summary: normalizedSummary,
          )
        : '';
    final diffSummary = diffText.isEmpty ? null : parseCodexDiffText(diffText);
    final diffPreview = diffSummary == null
        ? ''
        : summarizeCodexDiff(diffSummary);
    final effectiveSummary =
        effectiveToolType == 'file' && diffPreview.isNotEmpty
        ? diffPreview
        : normalizedSummary.isNotEmpty
        ? normalizedSummary
        : (existingCardData['summary'] ?? '').toString();
    final effectiveProgress =
        effectiveToolType == 'file' && diffPreview.isNotEmpty
        ? diffPreview
        : normalizedProgress.isNotEmpty
        ? normalizedProgress
        : (existingCardData['progress'] ?? '').toString();
    final resolvedFilePath = effectiveToolType == 'file'
        ? _resolveFilePath(raw) ??
              (diffSummary?.primaryPath.trim().isNotEmpty == true
                  ? diffSummary!.primaryPath
                  : null) ??
              (existingCardData['filePath'] ?? '').toString()
        : '';
    final cardData = <String, dynamic>{
      'type': 'agent_tool_summary',
      'uiStyle': 'codex_tool',
      'taskId': taskId,
      'toolName': toolInfo.toolName,
      'displayName': toolInfo.displayName,
      'toolTitle': effectiveTitle,
      'cardId': cardId,
      'toolType': effectiveToolType,
      if (toolInfo.serverName != null) 'serverName': toolInfo.serverName,
      'status': status,
      'summary': effectiveSummary,
      'progress': effectiveProgress,
      'argsJson': toolInfo.argsJson.isNotEmpty
          ? toolInfo.argsJson
          : (existingCardData['argsJson'] ?? _safeJson(raw)).toString(),
      'resultPreviewJson': toolInfo.resultPreviewJson.isNotEmpty
          ? toolInfo.resultPreviewJson
          : (existingCardData['resultPreviewJson'] ?? '').toString(),
      'rawResultJson': toolInfo.rawResultJson.isNotEmpty
          ? toolInfo.rawResultJson
          : _safeJson(raw),
      'terminalOutput': effectiveTerminalOutput,
      'terminalOutputDelta': normalizedProgress,
      'showTerminalOutput':
          (effectiveTerminalOutput.isNotEmpty && diffText.isEmpty) ||
          effectiveToolType == 'terminal',
      'showRawResult': true,
    };
    if (effectiveToolType == 'file') {
      cardData.addAll(<String, dynamic>{
        'diffText': diffText,
        'showDiff': diffText.isNotEmpty,
        'filePath': resolvedFilePath,
        'changedFiles': diffSummary?.changedFileCount ?? 0,
        'additions': diffSummary?.additions ?? 0,
        'deletions': diffSummary?.deletions ?? 0,
      });
    }
    final startTime = _startTimeForEntry(
      runtime,
      cardId,
      existingMessage: existing,
    );
    final message = ChatMessageModel(
      id: cardId,
      type: 2,
      user: 3,
      content: {'cardData': cardData, 'id': cardId},
      streamMeta: streamMeta,
      createAt: DateTime.fromMillisecondsSinceEpoch(startTime),
    );
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = existing!.copyWith(
        content: {'cardData': cardData, 'id': cardId},
        streamMeta: streamMeta,
      );
    }
    runtime.lastAgentToolType = effectiveToolType;
  }

  void _upsertCodexRequestCard(
    ChatConversationRuntimeState runtime, {
    required String cardId,
    required String taskId,
    required Object? requestId,
    required String requestKind,
    required String title,
    required String detail,
    required Map<String, dynamic> params,
    required Map<String, dynamic> streamMeta,
    String? questionId,
  }) {
    _touchActiveTurn(runtime, taskId);
    final cardData = <String, dynamic>{
      'type': 'codex_request',
      'taskId': taskId,
      'requestId': requestId,
      'requestKind': requestKind,
      'title': title,
      'detail': detail,
      'questionId': questionId,
      'rawParamsJson': _safeJson(params),
      'status': 'pending',
    };
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    final existing = index == -1 ? null : runtime.messages[index];
    final startTime = _startTimeForEntry(
      runtime,
      cardId,
      existingMessage: existing,
    );
    final message = ChatMessageModel(
      id: cardId,
      type: 2,
      user: 3,
      content: {'cardData': cardData, 'id': cardId},
      streamMeta: streamMeta,
      createAt: DateTime.fromMillisecondsSinceEpoch(startTime),
    );
    if (index == -1) {
      runtime.messages.insert(0, message);
    } else {
      runtime.messages[index] = runtime.messages[index].copyWith(
        content: {'cardData': cardData, 'id': cardId},
        streamMeta: streamMeta,
      );
    }
    runtime.isAiResponding = true;
  }

  String? _deduplicateReplayDelta(
    ChatConversationRuntimeState runtime, {
    required String entryId,
    required String existingText,
    required String delta,
    required bool hasLiveCache,
  }) {
    if (delta.isEmpty || hasLiveCache || existingText.isEmpty) {
      runtime.codexReplayDeltaOffsets.remove(entryId);
      return delta;
    }
    final previousOffset = runtime.codexReplayDeltaOffsets[entryId] ?? 0;
    final safeOffset = previousOffset.clamp(0, existingText.length).toInt();
    final remaining = existingText.substring(safeOffset);
    if (!remaining.startsWith(delta)) {
      runtime.codexReplayDeltaOffsets[entryId] = existingText.length;
      return delta;
    }
    final nextOffset = safeOffset + delta.length;
    if (nextOffset >= existingText.length) {
      runtime.codexReplayDeltaOffsets.remove(entryId);
    } else {
      runtime.codexReplayDeltaOffsets[entryId] = nextOffset;
    }
    return null;
  }

  void _completeItem(
    ChatConversationRuntimeState runtime,
    String taskId,
    String? itemId,
    Map<String, dynamic> params,
  ) {
    final item = _asStringMap(params['item']) ?? params;
    final itemType = canonicalCodexItemType(_string(item['type']));
    final text =
        _extractText(item['text']) ??
        _extractText(item['message']) ??
        _extractText(item['content']) ??
        '';
    if (itemType == 'agentMessage') {
      final messageId = '${itemId ?? taskId}-codex-agent';
      final existingText = _assistantTextForEntry(runtime, messageId);
      if (text.isNotEmpty && existingText.isEmpty) {
        _appendAssistantText(
          runtime,
          parentTaskId: taskId,
          entryId: messageId,
          delta: text,
          isFinal: true,
        );
      } else if (text.isNotEmpty && text != existingText) {
        if (text.startsWith(existingText)) {
          _appendAssistantText(
            runtime,
            parentTaskId: taskId,
            entryId: messageId,
            delta: text.substring(existingText.length),
            isFinal: true,
          );
        } else {
          _appendAssistantText(
            runtime,
            parentTaskId: taskId,
            entryId: messageId,
            delta: text,
            isFinal: true,
            replace: true,
          );
        }
      }
      _markAssistantEntryFinal(runtime, taskId, messageId);
      runtime.currentAiMessages.remove('${itemId ?? taskId}-codex-agent');
      runtime.codexReplayDeltaOffsets.remove(messageId);
    }
    if (itemType == 'reasoning') {
      // Keep the thinking card streaming until the entire turn ends.
      // _completeTurn() will call _finalizeThinkingCardsForTask() once
      // turn/completed (or thread/closed/inactive) arrives.
      runtime.codexReplayDeltaOffsets.remove(
        '${itemId ?? taskId}-codex-thinking',
      );
    }
    if (isCodexToolItemType(itemType)) {
      final toolInfo = normalizeCodexToolCall(
        item,
        itemType: itemType,
        fallbackStatus: 'success',
      );
      final completedItemId = itemId ?? _string(item['id']) ?? taskId;
      final suffix = codexToolCardSuffix(toolInfo.toolType, itemType: itemType);
      final cardId = '$completedItemId-codex-$suffix';
      _upsertToolCard(
        runtime,
        cardId: cardId,
        taskId: taskId,
        toolType: toolInfo.toolType,
        title: toolInfo.toolTitle,
        status: toolInfo.status,
        summary: toolInfo.summary,
        progress: toolInfo.progress,
        terminalOutput: toolInfo.terminalOutput,
        raw: item,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: taskId,
          entryId: cardId,
          kind: toolInfo.status == 'running'
              ? 'tool_progress'
              : 'tool_completed',
          isFinal: toolInfo.status != 'running',
        ),
        touchTurn: false,
      );
      runtime.codexReplayDeltaOffsets.remove(cardId);
      return;
    }
    final completedItemId = itemId ?? taskId;
    for (final suffix in const [
      'command',
      'file',
      'plan',
      'search',
      'workspace',
      'browser',
      'image',
      'tool',
    ]) {
      _markToolCardComplete(runtime, '$completedItemId-codex-$suffix');
    }
  }

  void _completeRawResponseItem(
    ChatConversationRuntimeState runtime,
    String taskId,
    Map<String, dynamic> params,
  ) {
    final item = _asStringMap(params['item']) ?? params;
    final itemType = _string(item['type']) ?? '';
    if (isCodexToolOutputItemType(itemType)) {
      _completeRawResponseOutputItem(runtime, taskId, params, item, itemType);
      return;
    }
    if (!isCodexToolItemType(itemType)) {
      return;
    }
    final rawItemId = _rawResponseItemId(params, item, taskId);
    final toolInfo = normalizeCodexToolCall(
      item,
      itemType: itemType,
      fallbackStatus: 'success',
    );
    final suffix = codexToolCardSuffix(toolInfo.toolType, itemType: itemType);
    final cardId = '$rawItemId-codex-$suffix';
    _upsertToolCard(
      runtime,
      cardId: cardId,
      taskId: taskId,
      toolType: toolInfo.toolType,
      title: toolInfo.toolTitle,
      status: toolInfo.status,
      summary: toolInfo.summary,
      progress: toolInfo.progress,
      terminalOutput: toolInfo.terminalOutput,
      raw: item,
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: taskId,
        entryId: cardId,
        kind: toolInfo.status == 'running' ? 'tool_progress' : 'tool_completed',
        isFinal: toolInfo.status != 'running',
      ),
      touchTurn: false,
    );
    runtime.codexReplayDeltaOffsets.remove(cardId);
  }

  void _completeRawResponseOutputItem(
    ChatConversationRuntimeState runtime,
    String taskId,
    Map<String, dynamic> params,
    Map<String, dynamic> item,
    String itemType,
  ) {
    final callId = _firstString([
      item['callId'],
      item['call_id'],
      params['callId'],
      params['call_id'],
    ]);
    final existingCardId = callId == null
        ? null
        : _findToolCardIdForCallId(runtime, callId);
    final existingMessage = existingCardId == null
        ? null
        : runtime.messages.cast<ChatMessageModel?>().firstWhere(
            (message) => message?.id == existingCardId,
            orElse: () => null,
          );
    final existing = existingCardId == null
        ? null
        : _toolCardData(runtime, existingCardId);
    final fallbackToolType =
        (existing?['toolType'] ?? '').toString().trim().isNotEmpty
        ? (existing!['toolType'] ?? '').toString()
        : itemType == 'tool_search_output'
        ? 'search'
        : 'tool';
    final fallbackTitle =
        (existing?['toolTitle'] ?? existing?['displayName'] ?? '')
            .toString()
            .trim();
    final toolInfo = normalizeCodexToolCall(
      item,
      itemType: itemType,
      fallbackToolType: fallbackToolType,
      fallbackTitle: fallbackTitle.isEmpty ? null : fallbackTitle,
      fallbackStatus: 'success',
    );
    final rawItemId = _rawResponseItemId(params, item, taskId);
    final suffix = codexToolCardSuffix(toolInfo.toolType, itemType: itemType);
    final cardId = existingCardId ?? '$rawItemId-codex-$suffix';
    final outputText = _extractCodexRawOutputText(item).trimRight();
    final existingTerminalOutput = (existing?['terminalOutput'] ?? '')
        .toString();
    final terminalOutput = toolInfo.toolType == 'terminal'
        ? _trimTerminalOutput(
            [
              existingTerminalOutput.trimRight(),
              outputText,
            ].where((part) => part.isNotEmpty).join('\n'),
          )
        : existingTerminalOutput;
    final summary = outputText.isNotEmpty
        ? _compactTitle(outputText, maxLength: 96)
        : toolInfo.summary;
    _upsertToolCard(
      runtime,
      cardId: cardId,
      taskId: taskId,
      toolType: toolInfo.toolType,
      title: toolInfo.toolTitle,
      status: toolInfo.status,
      summary: summary,
      progress: summary,
      terminalOutput: terminalOutput,
      raw: item,
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: taskId,
        entryId: cardId,
        kind: 'tool_completed',
        isFinal: true,
        existingMessage: existingMessage,
      ),
      touchTurn: false,
    );
    runtime.codexReplayDeltaOffsets.remove(cardId);
  }

  String _rawResponseItemId(
    Map<String, dynamic> params,
    Map<String, dynamic> item,
    String taskId,
  ) {
    return _firstString([
          params['itemId'],
          params['item_id'],
          item['id'],
          item['callId'],
          item['call_id'],
          params['callId'],
          params['call_id'],
        ]) ??
        '$taskId-${_stableCodexItemKey(item)}';
  }

  void _completeStandaloneProcess(
    ChatConversationRuntimeState runtime,
    String taskId,
    Map<String, dynamic> params,
    String method,
  ) {
    final standaloneId = _standaloneProcessId(params, method: method);
    final cardId = '$standaloneId-codex-command';
    final existing = _toolCardData(runtime, cardId);
    final existingOutput = (existing?['terminalOutput'] ?? '').toString();
    final stdout = _streamOutputBlock(params['stdout'], stream: 'stdout');
    final stderr = _streamOutputBlock(params['stderr'], stream: 'stderr');
    final output = _trimTerminalOutput(existingOutput + stdout + stderr);
    final exitCode = _asInt(params['exitCode'] ?? params['exit_code']);
    final status = exitCode == null || exitCode == 0 ? 'success' : 'error';
    final title =
        (existing?['toolTitle'] ?? existing?['displayName'])?.toString() ??
        _standaloneCommandTitle(params, fallback: standaloneId);
    final summary = exitCode == null
        ? 'Command completed'
        : 'Command exited with code $exitCode';
    _upsertToolCard(
      runtime,
      cardId: cardId,
      taskId: taskId,
      toolType: 'terminal',
      title: title,
      status: status,
      summary: summary,
      progress: summary,
      terminalOutput: output,
      raw: <String, dynamic>{
        ...params,
        'type': method == 'process/exited' ? 'processExecution' : 'commandExec',
      },
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: taskId,
        entryId: cardId,
        kind: 'tool_completed',
        isFinal: true,
      ),
      touchTurn: false,
    );
    runtime.codexReplayDeltaOffsets.remove(cardId);
  }

  void _completeTurn(
    ChatConversationRuntimeState runtime,
    String taskId, {
    bool appendCancelIfEmpty = true,
  }) {
    final isManualCancel =
        appendCancelIfEmpty &&
        taskId == runtime.currentDispatchTaskId &&
        !_hasVisibleAssistantTextForTask(runtime, taskId);
    if (isManualCancel) {
      _appendAssistantText(
        runtime,
        parentTaskId: taskId,
        entryId: '$taskId-cancelled',
        delta: '任务已取消',
        isFinal: true,
        replace: true,
      );
    }
    runtime.isAiResponding = false;
    runtime.isExecutingTask = false;
    runtime.isCheckingExecutableTask = false;
    runtime.currentDispatchTaskId = null;
    runtime.currentAiMessages.clear();
    runtime.currentThinkingMessages.remove(taskId);
    runtime.deepThinkingContent = '';
    runtime.isDeepThinking = false;
    runtime.currentThinkingStage = ThinkingStage.complete.value;
    _markAssistantMessagesFinalForTask(runtime, taskId);
    _finalizeThinkingCardsForTask(runtime, taskId);
    _markToolCardsCompleteForTask(runtime, taskId);
  }

  bool _hasVisibleAssistantTextForTask(
    ChatConversationRuntimeState runtime,
    String taskId,
  ) {
    for (final message in runtime.messages) {
      if (message.type != 1 || message.user != 2) {
        continue;
      }
      if ((message.streamMeta?['parentTaskId'] ?? '').toString() != taskId) {
        continue;
      }
      if (message.streamMeta?['isFinal'] == true) {
        return true;
      }
      if ((message.text ?? '').trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  void _markToolCardComplete(
    ChatConversationRuntimeState runtime,
    String cardId,
  ) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    if (index == -1) return;
    final existing = runtime.messages[index];
    final cardData = Map<String, dynamic>.from(existing.cardData ?? const {});
    final currentStatus = _string(cardData['status'])?.toLowerCase();
    if (currentStatus == 'error' ||
        currentStatus == 'timeout' ||
        currentStatus == 'interrupted' ||
        currentStatus == 'cancelled' ||
        currentStatus == 'canceled') {
      return;
    }
    cardData['status'] = 'success';
    final parentTaskId =
        _string(cardData['taskId']) ??
        _string(existing.streamMeta?['parentTaskId']);
    runtime.messages[index] = existing.copyWith(
      content: {'cardData': cardData, 'id': cardId},
      streamMeta: parentTaskId == null
          ? existing.streamMeta
          : _streamMeta(
              runtime,
              parentTaskId: parentTaskId,
              entryId: cardId,
              kind: 'tool_completed',
              existingMessage: existing,
            ),
    );
  }

  String _assistantTextForEntry(
    ChatConversationRuntimeState runtime,
    String messageId,
  ) {
    final runtimeText = runtime.currentAiMessages[messageId];
    if (runtimeText != null) {
      return runtimeText;
    }
    final index = runtime.messages.indexWhere(
      (message) => message.id == messageId,
    );
    return index == -1 ? '' : runtime.messages[index].text ?? '';
  }

  void _markAssistantEntryFinal(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
    String messageId,
  ) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index == -1) return;
    final existing = runtime.messages[index];
    runtime.messages[index] = existing.copyWith(
      isLoading: false,
      isError: false,
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: parentTaskId,
        entryId: messageId,
        kind: 'text_snapshot',
        isFinal: true,
        existingMessage: existing,
      ),
    );
  }

  void _markAssistantMessagesFinalForTask(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
  ) {
    for (var index = 0; index < runtime.messages.length; index += 1) {
      final message = runtime.messages[index];
      if (message.type != 1 || message.user != 2) {
        continue;
      }
      if (_string(message.streamMeta?['parentTaskId']) != parentTaskId) {
        continue;
      }
      runtime.messages[index] = message.copyWith(
        isLoading: false,
        isError: false,
        streamMeta: _streamMeta(
          runtime,
          parentTaskId: parentTaskId,
          entryId: message.id,
          kind: 'text_snapshot',
          isFinal: true,
          existingMessage: message,
        ),
      );
    }
  }

  void _finalizeThinkingCard(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
    String cardId,
  ) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    if (index == -1) return;
    final existing = runtime.messages[index];
    final existingCardData = existing.cardData;
    if (existingCardData?['type'] != 'deep_thinking') return;
    final cardData = Map<String, dynamic>.from(existingCardData!);
    final startTime =
        _asInt(cardData['startTime']) ??
        _startTimeForEntry(runtime, cardId, existingMessage: existing);
    cardData['isLoading'] = false;
    cardData['stage'] = ThinkingStage.complete.value;
    cardData['taskID'] = parentTaskId;
    cardData['cardId'] = cardId;
    cardData['startTime'] = startTime;
    cardData['endTime'] ??= DateTime.now().millisecondsSinceEpoch;
    cardData['isCollapsible'] = true;
    cardData['thinkingContent'] = (cardData['thinkingContent'] ?? '')
        .toString();
    runtime.messages[index] = existing.copyWith(
      content: {'cardData': cardData, 'id': cardId},
      streamMeta: _streamMeta(
        runtime,
        parentTaskId: parentTaskId,
        entryId: cardId,
        kind: 'thinking_snapshot',
        isFinal: true,
        existingMessage: existing,
      ),
    );
  }

  void _finalizeThinkingCardsForTask(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
  ) {
    final cardIds = runtime.messages
        .where((message) {
          final cardData = message.cardData;
          if (cardData?['type'] != 'deep_thinking') {
            return false;
          }
          final cardTaskId =
              _string(cardData?['taskID']) ??
              _string(message.streamMeta?['parentTaskId']);
          return cardTaskId == parentTaskId;
        })
        .map((message) => message.id)
        .toList(growable: false);
    for (final cardId in cardIds) {
      _finalizeThinkingCard(runtime, parentTaskId, cardId);
    }
  }

  void _markToolCardsCompleteForTask(
    ChatConversationRuntimeState runtime,
    String parentTaskId,
  ) {
    final cardIds = runtime.messages
        .where((message) {
          final cardData = message.cardData;
          if (cardData?['type'] != 'agent_tool_summary') {
            return false;
          }
          final cardTaskId =
              _string(cardData?['taskId']) ??
              _string(message.streamMeta?['parentTaskId']);
          if (cardTaskId != parentTaskId) {
            return false;
          }
          final status = _string(cardData?['status'])?.toLowerCase();
          return status == null ||
              status == 'running' ||
              status == 'pending' ||
              status == 'progress';
        })
        .map((message) => message.id)
        .toList(growable: false);
    for (final cardId in cardIds) {
      _markToolCardComplete(runtime, cardId);
    }
  }

  Map<String, dynamic>? _toolCardData(
    ChatConversationRuntimeState runtime,
    String cardId,
  ) {
    final index = runtime.messages.indexWhere(
      (message) => message.id == cardId,
    );
    if (index == -1) {
      return null;
    }
    final cardData = runtime.messages[index].cardData;
    if (cardData?['type'] != 'agent_tool_summary') {
      return null;
    }
    return cardData;
  }

  String? _findToolCardIdForCallId(
    ChatConversationRuntimeState runtime,
    String callId,
  ) {
    final normalizedCallId = callId.trim();
    if (normalizedCallId.isEmpty) {
      return null;
    }
    for (final suffix in const <String>[
      'command',
      'file',
      'plan',
      'search',
      'workspace',
      'browser',
      'image',
      'tool',
    ]) {
      final cardId = '$normalizedCallId-codex-$suffix';
      if (_toolCardData(runtime, cardId) != null) {
        return cardId;
      }
    }
    for (final message in runtime.messages) {
      final cardData = message.cardData;
      if (cardData?['type'] != 'agent_tool_summary') {
        continue;
      }
      if (_toolCardContainsCallId(cardData!, normalizedCallId)) {
        return message.id;
      }
    }
    return null;
  }

  bool _toolCardContainsCallId(Map<String, dynamic> cardData, String callId) {
    for (final key in const <String>[
      'rawResultJson',
      'resultPreviewJson',
      'argsJson',
    ]) {
      final text = (cardData[key] ?? '').toString().trim();
      if (text.isEmpty) {
        continue;
      }
      final decoded = _decodeJsonValue(text);
      if (_valueContainsCallId(decoded, callId)) {
        return true;
      }
    }
    return false;
  }

  bool _valueContainsCallId(dynamic value, String callId) {
    if (value == null) {
      return false;
    }
    if (value is String || value is num || value is bool) {
      return value.toString() == callId;
    }
    final map = _asStringMap(value);
    if (map != null) {
      if (_firstString([map['callId'], map['call_id'], map['id']]) == callId) {
        return true;
      }
      return map.values.any((nested) => _valueContainsCallId(nested, callId));
    }
    if (value is List) {
      return value.any((nested) => _valueContainsCallId(nested, callId));
    }
    return false;
  }

  dynamic _decodeJsonValue(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  String _stableCodexItemKey(Map<String, dynamic> item) {
    final stablePayload = <String, dynamic>{
      'type': item['type'],
      'name': item['name'],
      'namespace': item['namespace'],
      'arguments': item['arguments'],
      'action': item['action'],
      'execution': item['execution'],
      'query': item['query'],
      'output': item['output'],
      'status': item['status'],
    };
    return 'raw-${_stableTextHash(_safeJson(stablePayload))}';
  }

  String _stableTextHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> _streamMeta(
    ChatConversationRuntimeState runtime, {
    required String parentTaskId,
    required String entryId,
    required String kind,
    bool isFinal = false,
    ChatMessageModel? existingMessage,
  }) {
    final seq = _sequenceForEntry(
      runtime,
      entryId,
      existingMessage: existingMessage,
    );
    return ensureAgentStreamMessageMeta(
          existingMessage?.streamMeta,
          seq: seq,
          roundIndex: seq,
          kind: kind,
          parentTaskId: parentTaskId,
          entryId: entryId,
          isFinal: isFinal,
        ) ??
        <String, dynamic>{};
  }

  int _sequenceForEntry(
    ChatConversationRuntimeState runtime,
    String entryId, {
    ChatMessageModel? existingMessage,
  }) {
    final key = entryId.trim();
    final cached = runtime.codexEntrySequences[key];
    if (cached != null) {
      return cached;
    }
    final existingSeq = _asInt(existingMessage?.streamMeta?['seq']);
    if (existingSeq != null && existingSeq > 0) {
      runtime.codexEntrySequences[key] = existingSeq;
      if (runtime.codexNextEntrySequence < existingSeq) {
        runtime.codexNextEntrySequence = existingSeq;
      }
      return existingSeq;
    }
    runtime.codexNextEntrySequence += 1;
    runtime.codexEntrySequences[key] = runtime.codexNextEntrySequence;
    return runtime.codexNextEntrySequence;
  }

  int _startTimeForEntry(
    ChatConversationRuntimeState runtime,
    String entryId, {
    ChatMessageModel? existingMessage,
  }) {
    final key = entryId.trim();
    final cached = runtime.codexEntryStartTimes[key];
    if (cached != null) {
      return cached;
    }
    final existingStart =
        _asInt(existingMessage?.cardData?['startTime']) ??
        existingMessage?.createAt.millisecondsSinceEpoch;
    final startTime = existingStart ?? DateTime.now().millisecondsSinceEpoch;
    runtime.codexEntryStartTimes[key] = startTime;
    return startTime;
  }

  bool _removeCodexDebugStatusCards(ChatConversationRuntimeState runtime) {
    final before = runtime.messages.length;
    runtime.messages.removeWhere((message) {
      final cardData = message.cardData;
      if (cardData == null) return false;
      final toolName = _string(cardData['toolName']);
      final title =
          _string(cardData['toolTitle']) ?? _string(cardData['displayName']);
      return toolName == 'codex.status' &&
          (title == 'codex/stderr' || title == 'codex/parseError');
    });
    return runtime.messages.length != before;
  }

  String _standaloneProcessId(
    Map<String, dynamic> params, {
    required String method,
  }) {
    return _firstString([
          params['processId'],
          params['process_id'],
          params['processHandle'],
          params['process_handle'],
          params['id'],
        ]) ??
        method.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-');
  }

  String _standaloneCommandTitle(
    Map<String, dynamic> params, {
    required String fallback,
  }) {
    final command =
        _commandTextFromValue(params['command']) ??
        _commandTextFromValue(_toolArguments(params)['command']) ??
        _commandTextFromValue(_asStringMap(params['action'])?['command']) ??
        _firstString([params['processId'], params['processHandle']]);
    if (command == null || command.trim().isEmpty) {
      return _compactTitle(fallback, maxLength: 48);
    }
    return _compactTitle(command, maxLength: 48);
  }

  String _standaloneProcessOutputDelta(Map<String, dynamic> params) {
    final decoded =
        _decodeBase64Output(params['deltaBase64']) ??
        _decodeBase64Output(params['delta_base64']) ??
        _extractText(params['delta']) ??
        _extractText(params['output']) ??
        _extractText(params['text']) ??
        '';
    final stream = _string(params['stream'])?.toLowerCase();
    if (decoded.isEmpty || stream == null || stream == 'stdout') {
      return decoded;
    }
    return _streamOutputBlock(decoded, stream: stream);
  }

  String _streamOutputBlock(dynamic value, {required String stream}) {
    final text = _extractText(value) ?? '';
    if (text.isEmpty) {
      return '';
    }
    final normalizedStream = stream.toLowerCase();
    if (normalizedStream == 'stdout') {
      return text;
    }
    final needsLeadingNewline = text.startsWith('\n') ? '' : '\n';
    final needsTrailingNewline = text.endsWith('\n') ? '' : '\n';
    return '$needsLeadingNewline[$normalizedStream]\n$text$needsTrailingNewline';
  }

  String _extractCodexRawOutputText(Map<String, dynamic> item) {
    final output = item['output'];
    final text =
        _extractText(output) ??
        _extractText(item['tools']) ??
        _extractText(item['result']) ??
        _extractText(item['content']) ??
        '';
    if (text.trim().isNotEmpty) {
      return text;
    }
    if (output != null) {
      return _safeJson(output);
    }
    return '';
  }

  String _approvalTitle(String method, Map<String, dynamic> params) {
    if (method.contains('commandExecution')) {
      return _commandTitle(params);
    }
    if (method.contains('fileChange')) {
      return _fileChangeTitle(params, fallback: 'Codex file approval');
    }
    return 'Codex approval';
  }

  String _approvalDetail(Map<String, dynamic> params) {
    return _extractText(params['reason']) ??
        _extractText(params['description']) ??
        _extractText(params['command']) ??
        _safeJson(params);
  }

  String _commandTitle(Map<String, dynamic> params) {
    final command =
        _commandTextFromValue(params['command']) ??
        _commandTextFromValue(_toolArguments(params)['command']) ??
        _commandTextFromValue(_asStringMap(params['item'])?['command']) ??
        _commandTextFromValue(_asStringMap(params['action'])?['command']) ??
        _commandTextFromValue(
          _asStringMap(_asStringMap(params['item'])?['action'])?['command'],
        ) ??
        _extractText(params['cmd']);
    if (command == null || command.trim().isEmpty) {
      return 'Codex command';
    }
    return _compactTitle(command, maxLength: 48);
  }

  String _fileChangeTitle(
    Map<String, dynamic> params, {
    String fallback = 'Codex file change',
  }) {
    final path = _resolveFilePath(params);
    if (path == null) {
      return fallback;
    }
    final name = _lastPathSegment(path) ?? path;
    return _compactTitle('Edit $name', maxLength: 42);
  }

  String? _resolveFilePath(Map<String, dynamic> params) {
    final args = _toolArguments(params);
    return _firstString([
          params['path'],
          params['filePath'],
          params['file_path'],
          params['filename'],
          params['fileName'],
          args['path'],
          args['filePath'],
          args['file_path'],
          args['filename'],
          args['fileName'],
          _firstPathFromList(params['files']),
          _firstPathFromList(params['changes']),
          _firstPathFromList(args['files']),
          _firstPathFromList(args['changes']),
          _asStringMap(params['item'])?['path'],
          _asStringMap(params['item'])?['filePath'],
          _asStringMap(params['item'])?['file_path'],
        ]) ??
        extractCodexDiffPath(params);
  }

  String _resolveFileDiffText({
    required Map<String, dynamic> existingCardData,
    required Map<String, dynamic> raw,
    required String terminalOutput,
    required String progress,
    required String summary,
  }) {
    final fromExisting = (existingCardData['diffText'] ?? '').toString();
    final fromCurrent = extractCodexDiffText(
      raw,
      outputText: terminalOutput,
      progress: progress,
      summary: summary,
    );
    if (fromCurrent != null && fromCurrent.trim().isNotEmpty) {
      return fromCurrent;
    }
    return fromExisting.trim().isEmpty ? '' : fromExisting;
  }

  Map<String, dynamic> _toolArguments(Map<String, dynamic> params) {
    for (final key in const <String>['arguments', 'args', 'input']) {
      final map = _asStringMap(params[key]);
      if (map != null) {
        return map;
      }
      final text = _string(params[key]);
      if (text == null || text.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        continue;
      }
    }
    final item = _asStringMap(params['item']);
    if (item != null && item != params) {
      return _toolArguments(item);
    }
    return const <String, dynamic>{};
  }

  String? _firstPathFromList(dynamic value) {
    if (value is! List) {
      return null;
    }
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        return item.trim();
      }
      final map = _asStringMap(item);
      final path = _firstString([
        map?['path'],
        map?['filePath'],
        map?['file_path'],
        map?['filename'],
        map?['fileName'],
      ]);
      if (path != null) {
        return path;
      }
    }
    return null;
  }

  String? _lastPathSegment(String path) {
    final normalized = path.trim().replaceAll(RegExp(r'[/\\]+$'), '');
    if (normalized.isEmpty) {
      return null;
    }
    final parts = normalized
        .split(RegExp(r'[/\\]+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? normalized : parts.last;
  }

  String _compactTitle(String value, {required int maxLength}) {
    final normalized = value
        .trim()
        .split('\n')
        .first
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  _CodexQuestion _firstQuestion(Map<String, dynamic> params) {
    final questions = params['questions'];
    if (questions is List && questions.isNotEmpty) {
      final first = _asStringMap(questions.first);
      if (first != null) {
        final id =
            _string(first['id']) ?? _string(first['questionId']) ?? 'answer';
        final title =
            _string(first['label']) ??
            _string(first['title']) ??
            _string(first['question']) ??
            'Codex needs input';
        final detail =
            _string(first['description']) ??
            _string(first['placeholder']) ??
            title;
        return _CodexQuestion(id: id, title: title, detail: detail);
      }
    }
    final id =
        _string(params['questionId']) ?? _string(params['id']) ?? 'answer';
    final title =
        _string(params['question']) ??
        _string(params['title']) ??
        'Codex needs input';
    final detail = _string(params['description']) ?? title;
    return _CodexQuestion(id: id, title: title, detail: detail);
  }
}

class _CodexQuestion {
  const _CodexQuestion({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;
}

bool _isReasoningMethod(String method) {
  return method == 'item/reasoning/summaryPartAdded' ||
      method == 'item/reasoning/summaryTextDelta' ||
      method == 'item/reasoning/textDelta';
}

Map<String, dynamic>? _codexProtocolMsg(
  Map<String, dynamic> root, {
  int depth = 0,
}) {
  if (depth > 6) {
    return null;
  }
  final direct = _asStringMap(root['msg']);
  if (direct != null) {
    return direct;
  }
  for (final key in const <String>[
    'params',
    'message',
    'payload',
    'data',
    'event',
    'notification',
    'result',
  ]) {
    final nested = _asStringMap(root[key]);
    if (nested == null) {
      continue;
    }
    final msg = _codexProtocolMsg(nested, depth: depth + 1);
    if (msg != null) {
      return msg;
    }
  }
  return null;
}

Map<String, dynamic>? _codexProtocolMeta(
  Map<String, dynamic> root, {
  int depth = 0,
}) {
  if (depth > 6) {
    return null;
  }
  final direct = _asStringMap(root['_meta']);
  if (direct != null) {
    return direct;
  }
  for (final key in const <String>[
    'params',
    'message',
    'payload',
    'data',
    'event',
    'notification',
    'result',
  ]) {
    final nested = _asStringMap(root[key]);
    if (nested == null) {
      continue;
    }
    final meta = _codexProtocolMeta(nested, depth: depth + 1);
    if (meta != null) {
      return meta;
    }
  }
  return null;
}

String _normalizeCodexProtocolMsgType(String? rawType) {
  final value = rawType?.trim().toLowerCase() ?? '';
  if (value.isEmpty) {
    return '';
  }
  return value.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

Map<String, dynamic> _codexProtocolCommandItem(
  Map<String, dynamic> msg, {
  required String? status,
}) {
  final command = _commandTextFromValue(msg['command']);
  final exitCode = _asInt(msg['exitCode'] ?? msg['exit_code']);
  final explicitStatus =
      status ??
      _string(msg['status']) ??
      (exitCode == null
          ? 'completed'
          : exitCode == 0
          ? 'completed'
          : 'failed');
  return <String, dynamic>{
    ...msg,
    'id': _firstString([msg['callId'], msg['call_id'], msg['id']]),
    'callId': _firstString([msg['callId'], msg['call_id']]),
    'call_id': _firstString([msg['call_id'], msg['callId']]),
    'type': 'commandExecution',
    if (command != null) 'command': command,
    'cwd': msg['cwd'],
    'processId': msg['processId'] ?? msg['process_id'],
    'process_id': msg['process_id'] ?? msg['processId'],
    'aggregatedOutput':
        msg['aggregatedOutput'] ?? msg['aggregated_output'] ?? msg['output'],
    'aggregated_output':
        msg['aggregated_output'] ?? msg['aggregatedOutput'] ?? msg['output'],
    'stdout': msg['stdout'],
    'stderr': msg['stderr'],
    'exitCode': exitCode,
    'exit_code': exitCode,
    'status': explicitStatus,
  };
}

String _codexProtocolOutputDelta(Map<String, dynamic> msg) {
  final decoded =
      _decodeBase64Output(msg['chunk']) ??
      _decodeByteListOutput(msg['chunk']) ??
      _decodeBase64Output(msg['deltaBase64']) ??
      _decodeBase64Output(msg['delta_base64']) ??
      _extractText(msg['delta']) ??
      _extractText(msg['output']) ??
      _extractText(msg['text']) ??
      '';
  final stream = _string(msg['stream'])?.toLowerCase();
  if (decoded.isEmpty || stream == null || stream == 'stdout') {
    return decoded;
  }
  return _codexProtocolStreamOutputBlock(decoded, stream: stream);
}

String _codexProtocolFinalCommandOutput(Map<String, dynamic> msg) {
  final aggregated =
      _extractText(msg['aggregatedOutput']) ??
      _extractText(msg['aggregated_output']) ??
      '';
  if (aggregated.isNotEmpty) {
    return _trimTerminalOutput(aggregated);
  }
  final stdout = _codexProtocolStreamOutputBlock(
    _extractText(msg['stdout']) ?? '',
    stream: 'stdout',
  );
  final stderr = _codexProtocolStreamOutputBlock(
    _extractText(msg['stderr']) ?? '',
    stream: 'stderr',
  );
  final combined = _trimTerminalOutput(stdout + stderr);
  if (combined.trim().isNotEmpty) {
    return combined;
  }
  return _trimTerminalOutput(
    _extractText(msg['formattedOutput'] ?? msg['formatted_output']) ?? '',
  );
}

String _codexProtocolStreamOutputBlock(String text, {required String stream}) {
  if (text.isEmpty) {
    return '';
  }
  final normalizedStream = stream.toLowerCase();
  if (normalizedStream == 'stdout') {
    return text;
  }
  final needsLeadingNewline = text.startsWith('\n') ? '' : '\n';
  final needsTrailingNewline = text.endsWith('\n') ? '' : '\n';
  return '$needsLeadingNewline[$normalizedStream]\n$text$needsTrailingNewline';
}

Map<String, dynamic> _codexProtocolMcpToolItem(
  Map<String, dynamic> msg, {
  required String? status,
}) {
  final invocation =
      _asStringMap(msg['invocation']) ?? const <String, dynamic>{};
  final resultFields = _codexProtocolMcpResultFields(msg['result']);
  return <String, dynamic>{
    ...msg,
    'id': _firstString([msg['callId'], msg['call_id'], msg['id']]),
    'callId': _firstString([msg['callId'], msg['call_id']]),
    'call_id': _firstString([msg['call_id'], msg['callId']]),
    'type': 'mcpToolCall',
    'server': invocation['server'] ?? msg['server'],
    'tool': invocation['tool'] ?? msg['tool'],
    'arguments': invocation['arguments'] ?? msg['arguments'],
    'mcpAppResourceUri':
        msg['mcpAppResourceUri'] ?? msg['mcp_app_resource_uri'],
    'pluginId': msg['pluginId'] ?? msg['plugin_id'],
    'status': status ?? resultFields['status'] ?? msg['status'] ?? 'completed',
    ...resultFields,
  };
}

Map<String, dynamic> _codexProtocolMcpResultFields(dynamic value) {
  if (value == null) {
    return const <String, dynamic>{};
  }
  final map = _asStringMap(value);
  if (map != null) {
    if (map.containsKey('Ok') || map.containsKey('ok')) {
      return <String, dynamic>{
        'status': 'completed',
        'result': map['Ok'] ?? map['ok'],
      };
    }
    if (map.containsKey('Err') || map.containsKey('err')) {
      final error = map['Err'] ?? map['err'];
      return <String, dynamic>{
        'status': 'failed',
        'error': error is Map ? error : <String, dynamic>{'message': error},
      };
    }
  }
  return <String, dynamic>{'status': 'completed', 'result': value};
}

Map<String, dynamic> _codexProtocolWebSearchItem(
  Map<String, dynamic> msg, {
  required String status,
}) {
  final action = _asStringMap(msg['action']);
  return <String, dynamic>{
    ...msg,
    'id': _firstString([msg['callId'], msg['call_id'], msg['id']]),
    'callId': _firstString([msg['callId'], msg['call_id']]),
    'call_id': _firstString([msg['call_id'], msg['callId']]),
    'type': 'webSearch',
    'query': msg['query'] ?? action?['query'],
    'action': msg['action'],
    'status': status,
  };
}

Map<String, dynamic> _codexProtocolPatchItem(
  Map<String, dynamic> msg, {
  required String? status,
}) {
  final success = msg['success'];
  final normalizedStatus =
      status ??
      _string(msg['status']) ??
      (success == false ? 'failed' : 'completed');
  return <String, dynamic>{
    ...msg,
    'id': _firstString([msg['callId'], msg['call_id'], msg['id']]),
    'callId': _firstString([msg['callId'], msg['call_id']]),
    'call_id': _firstString([msg['call_id'], msg['callId']]),
    'type': 'fileChange',
    'changes': msg['changes'],
    'stdout': msg['stdout'],
    'stderr': msg['stderr'],
    'success': success,
    'status': normalizedStatus,
  };
}

String _resolveCodexEventMethod({
  required Map<String, dynamic> event,
  required Map<String, dynamic> message,
}) {
  for (final envelope in _codexEnvelopeMaps(message)) {
    final normalized = _normalizeCodexEventMethod(_string(envelope['method']));
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  if (!identical(event, message)) {
    for (final envelope in _codexEnvelopeMaps(event)) {
      final normalized = _normalizeCodexEventMethod(
        _string(envelope['method']),
      );
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
  }
  for (final envelope in _codexEnvelopeMaps(message)) {
    final rawType = _string(envelope['type']);
    if (!_codexTypeLooksLikeEventMethod(rawType)) {
      continue;
    }
    final normalized = _normalizeCodexEventMethod(rawType);
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  if (!identical(event, message)) {
    for (final envelope in _codexEnvelopeMaps(event)) {
      final rawType = _string(envelope['type']);
      if (!_codexTypeLooksLikeEventMethod(rawType)) {
        continue;
      }
      final normalized = _normalizeCodexEventMethod(rawType);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
  }
  return '';
}

bool _codexTypeLooksLikeEventMethod(String? rawType) {
  final value = rawType?.trim() ?? '';
  if (value.isEmpty) {
    return false;
  }
  final normalized = _normalizeCodexEventMethod(value);
  return normalized.contains('/') ||
      normalized == 'error' ||
      _looksLikeStandaloneCodexItemType(value);
}

String _normalizeCodexEventMethod(String? rawMethod) {
  final value = rawMethod?.trim() ?? '';
  if (value.isEmpty) {
    return '';
  }
  final dotted = const <String, String>{
    'thread.started': 'thread/started',
    'turn.started': 'turn/started',
    'turn.completed': 'turn/completed',
    'turn.failed': 'turn/failed',
    'item.started': 'item/started',
    'item.updated': 'item/updated',
    'item.completed': 'item/completed',
  }[value];
  if (dotted != null) {
    return dotted;
  }
  if (_looksLikeStandaloneCodexItemType(value)) {
    return 'item/completed';
  }
  return value
      .replaceAll('/agent_message/', '/agentMessage/')
      .replaceAll('/command_execution/', '/commandExecution/')
      .replaceAll('/file_change/', '/fileChange/')
      .replaceAll('/mcp_tool_call/', '/mcpToolCall/');
}

Map<String, dynamic> _eventParams({
  required Map<String, dynamic> event,
  required Map<String, dynamic> message,
  required String method,
}) {
  final messageParams = _firstNestedParamsMap(message);
  if (messageParams != null && messageParams.isNotEmpty) {
    return messageParams;
  }
  final eventParams = _firstNestedParamsMap(event);
  if (eventParams != null && eventParams.isNotEmpty) {
    return eventParams;
  }
  if (_isItemLifecycleMethod(method)) {
    final item = _firstNestedItemMap(message) ?? _firstNestedItemMap(event);
    if (item != null) {
      return <String, dynamic>{
        ..._payloadWithoutEnvelope(message),
        'item': item,
      };
    }
    final directItem =
        _standaloneCodexItemPayload(message) ??
        _standaloneCodexItemPayload(event);
    if (directItem != null) {
      return <String, dynamic>{
        ..._topLevelCodexIds(message),
        ..._topLevelCodexIds(event),
        'item': directItem,
      };
    }
  }
  final messagePayload = _payloadWithoutEnvelope(message);
  if (messagePayload.isNotEmpty) {
    return messagePayload;
  }
  return _payloadWithoutEnvelope(event);
}

const List<String> _codexEnvelopeKeys = <String>[
  'message',
  'payload',
  'data',
  'event',
  'notification',
  'result',
];

Iterable<Map<String, dynamic>> _codexEnvelopeMaps(
  Map<String, dynamic> root, {
  int depth = 0,
}) sync* {
  if (depth > 6) {
    return;
  }
  yield root;
  final params = _asStringMap(root['params']);
  if (params != null) {
    yield* _codexEnvelopeMaps(params, depth: depth + 1);
  }
  for (final key in _codexEnvelopeKeys) {
    final nested = _asStringMap(root[key]);
    if (nested == null) {
      continue;
    }
    yield* _codexEnvelopeMaps(nested, depth: depth + 1);
  }
}

Map<String, dynamic>? _firstNestedParamsMap(
  Map<String, dynamic> root, {
  int depth = 0,
}) {
  if (depth > 6) {
    return null;
  }
  final direct = _asStringMap(root['params']);
  if (direct != null) {
    final nested = _firstNestedParamsMap(direct, depth: depth + 1);
    if (nested != null && nested.isNotEmpty) {
      return <String, dynamic>{..._topLevelCodexIds(root), ...nested};
    }
    if (direct.isNotEmpty) {
      return <String, dynamic>{..._topLevelCodexIds(root), ...direct};
    }
  }
  for (final key in _codexEnvelopeKeys) {
    final nested = _asStringMap(root[key]);
    if (nested == null) {
      continue;
    }
    final nestedParams = _firstNestedParamsMap(nested, depth: depth + 1);
    if (nestedParams != null && nestedParams.isNotEmpty) {
      return <String, dynamic>{..._topLevelCodexIds(root), ...nestedParams};
    }
  }
  return null;
}

Map<String, dynamic>? _firstNestedItemMap(
  Map<String, dynamic> root, {
  int depth = 0,
}) {
  if (depth > 6) {
    return null;
  }
  for (final key in const <String>['item', 'rawItem', 'responseItem']) {
    final item = _asStringMap(root[key]);
    if (item != null) {
      return item;
    }
  }
  final params = _asStringMap(root['params']);
  if (params != null) {
    final item = _firstNestedItemMap(params, depth: depth + 1);
    if (item != null) {
      return item;
    }
  }
  for (final key in _codexEnvelopeKeys) {
    final nested = _asStringMap(root[key]);
    if (nested == null) {
      continue;
    }
    final item = _firstNestedItemMap(nested, depth: depth + 1);
    if (item != null) {
      return item;
    }
  }
  return null;
}

bool _isItemLifecycleMethod(String method) {
  return method == 'item/started' ||
      method == 'item/updated' ||
      method == 'item/completed';
}

Map<String, dynamic> _payloadWithoutEnvelope(Map<String, dynamic> value) {
  final payload = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key == 'method' ||
        key == 'type' ||
        key == 'params' ||
        _codexEnvelopeKeys.contains(key)) {
      continue;
    }
    payload[key] = entry.value;
  }
  return payload;
}

Map<String, dynamic>? _standaloneCodexItemPayload(Map<String, dynamic> value) {
  final type = _string(value['type']);
  if (!_looksLikeStandaloneCodexItemType(type)) {
    return null;
  }
  return value;
}

bool _looksLikeStandaloneCodexItemType(String? itemType) {
  final canonicalItemType = canonicalCodexItemType(itemType);
  return canonicalItemType == 'agentMessage' ||
      canonicalItemType == 'reasoning' ||
      isCodexToolItemType(canonicalItemType);
}

Map<String, dynamic> _topLevelCodexIds(Map<String, dynamic> value) {
  final ids = <String, dynamic>{};
  final meta = _asStringMap(value['_meta']);
  if (meta != null) {
    for (final key in const <String>['threadId', 'thread_id']) {
      if (meta.containsKey(key)) {
        ids[key] = meta[key];
      }
    }
  }
  for (final key in const <String>[
    'threadId',
    'thread_id',
    'turnId',
    'turn_id',
    'itemId',
    'item_id',
  ]) {
    if (value.containsKey(key)) {
      ids[key] = value[key];
    }
  }
  return ids;
}

Map<String, dynamic>? _asStringMap(dynamic value) {
  if (value is! Map) return null;
  return value.map((key, nestedValue) => MapEntry(key.toString(), nestedValue));
}

String? _extractText(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  final map = _asStringMap(value);
  if (map != null) {
    return _firstString([
      map['text'],
      map['content'],
      map['message'],
      map['value'],
      map['delta'],
      map['summary'],
    ]);
  }
  if (value is List) {
    return value.map(_extractText).whereType<String>().join();
  }
  return value.toString();
}

String? _commandTextFromValue(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is List) {
    final parts = value
        .map(_extractText)
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? null : parts.join(' ');
  }
  return _extractText(value);
}

String? _decodeBase64Output(dynamic value) {
  final encoded = _string(value);
  if (encoded == null) {
    return null;
  }
  try {
    return utf8.decode(base64Decode(encoded), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

String? _decodeByteListOutput(dynamic value) {
  if (value is! List) {
    return null;
  }
  final bytes = <int>[];
  for (final item in value) {
    final byte = _asInt(item);
    if (byte == null || byte < 0 || byte > 255) {
      return null;
    }
    bytes.add(byte);
  }
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

String? _string(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _firstString(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _extractText(value)?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

String? _statusType(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _statusText(value);
    if (text != null && text.isNotEmpty) {
      return _normalizeStatus(text);
    }
  }
  return null;
}

String? _statusText(dynamic value) {
  if (value == null) return null;
  if (value is String || value is num || value is bool) {
    return value.toString();
  }
  final map = _asStringMap(value);
  if (map != null) {
    return _firstString([
      map['type'],
      map['status'],
      map['state'],
      map['value'],
      map['name'],
    ]);
  }
  return null;
}

String _normalizeStatus(String status) =>
    status.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

bool _statusIsActive(String? status) {
  return status == 'running' ||
      status == 'active' ||
      status == 'busy' ||
      status == 'inprogress' ||
      status == 'inflight' ||
      status == 'executing';
}

bool _statusIsInactive(String? status) {
  return status == 'idle' ||
      status == 'closed' ||
      status == 'completed' ||
      status == 'complete' ||
      status == 'notloaded' ||
      status == 'systemerror' ||
      status == 'failed' ||
      status == 'cancelled' ||
      status == 'canceled' ||
      status == 'interrupted';
}

bool _statusIsCancelled(String? status) {
  return status == 'cancelled' ||
      status == 'canceled' ||
      status == 'interrupted';
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _safeJson(dynamic value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value?.toString() ?? '';
  }
}

String _accountSummary(Map<String, dynamic> params) {
  final account = _asStringMap(params['account']) ?? params;
  final email = _string(account['email']);
  final plan = _string(account['planType']) ?? _string(account['plan_type']);
  final type = _string(account['type']);
  final parts = <String>[
    if (email != null) email,
    if (plan != null) plan,
    if (type != null && type != 'chatgpt') type,
  ];
  return parts.isEmpty ? _safeJson(params) : parts.join(' / ');
}

String _trimTerminalOutput(String value) {
  const maxChars = 64 * 1024;
  const maxLines = 600;
  var text = value;
  if (text.length > maxChars) {
    text = text.substring(text.length - maxChars);
  }
  final lines = text.split('\n');
  if (lines.length > maxLines) {
    text = lines.sublist(lines.length - maxLines).join('\n');
  }
  return text;
}
