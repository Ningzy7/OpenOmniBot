import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/chat/chat_page.dart';
import 'package:ui/features/home/pages/chat/mixins/agent_stream_handler.dart';
import 'package:ui/features/home/pages/chat/services/chat_conversation_runtime_coordinator.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/codex_event_reducer.dart';

void main() {
  late CodexEventReducer reducer;
  late ChatConversationRuntimeState runtime;

  setUp(() {
    reducer = const CodexEventReducer();
    runtime = ChatConversationRuntimeState(
      conversationId: 42,
      mode: kChatRuntimeModeCodex,
    );
  });

  tearDown(() {
    runtime.dispose();
  });

  test('maps agent message deltas into assistant text', () {
    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'delta': 'hello'},
        },
      },
    );

    expect(result.handled, isTrue);
    expect(runtime.messages.single.text, 'hello');
    expect(runtime.messages.single.user, 2);
  });

  test('maps reasoning deltas into deep thinking card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {'turnId': 'turn-1', 'delta': 'thinking'},
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'deep_thinking');
    expect(cardData['thinkingContent'], 'thinking');
    expect(cardData['isLoading'], isTrue);
  });

  test('maps command output deltas into terminal tool card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/commandExecution/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'cmd-1',
            'command': 'ls',
            'delta': 'file.txt\n',
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'terminal');
    expect(cardData['terminalOutput'], 'file.txt\n');
  });

  test('maps standalone command output deltas into terminal tool card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'command/exec/outputDelta',
          'params': {
            'processId': 'proc-1',
            'stream': 'stdout',
            'deltaBase64': base64Encode(utf8.encode('hello\n')),
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolName'], 'codex.commandExec');
    expect(cardData['terminalOutput'], 'hello\n');
    expect(cardData['status'], 'running');
  });

  test('maps process exit snapshots into completed terminal card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'process/outputDelta',
          'params': {
            'processHandle': 'proc-2',
            'stream': 'stderr',
            'deltaBase64': base64Encode(utf8.encode('warning\n')),
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'process/exited',
          'params': {
            'processHandle': 'proc-2',
            'exitCode': 1,
            'stdout': '',
            'stderr': 'failed\n',
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['status'], 'error');
    expect(cardData['terminalOutput'], contains('[stderr]'));
    expect(cardData['terminalOutput'], contains('warning'));
    expect(cardData['terminalOutput'], contains('failed'));
  });

  test('maps raw response read file calls into workspace tool card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call',
              'name': 'read_file',
              'call_id': 'call-read-1',
              'arguments': jsonEncode({'path': 'README.md'}),
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'workspace');
    expect(cardData['toolTitle'], 'Read README.md');
    expect(cardData['status'], 'success');
    expect(cardData['argsJson'], contains('README.md'));
  });

  test('maps raw response local shell calls into terminal tool card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'local_shell_call',
              'call_id': 'call-shell-1',
              'status': 'completed',
              'action': {
                'type': 'exec',
                'command': ['ls', '-la'],
                'working_directory': '/workspace',
              },
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolTitle'], 'ls -la');
    expect(cardData['status'], 'success');
    expect(cardData['argsJson'], contains('ls -la'));
  });

  test('maps raw exec_command calls into terminal tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call',
              'name': 'exec_command',
              'call_id': 'call-cmd-1',
              'arguments': jsonEncode({
                'cmd':
                    'cd ui && flutter test test/services/codex_event_reducer_test.dart',
              }),
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolTitle'], contains('flutter test'));
    expect(cardData['argsJson'], contains('flutter test'));
  });

  test('classifies raw rg exec_command calls as search tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call',
              'name': 'exec_command',
              'call_id': 'call-search-1',
              'arguments': jsonEncode({
                'cmd': 'rg -n "rawResponseItem" ui/lib ui/test',
              }),
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'search');
    expect(cardData['toolTitle'], 'rg -n "rawResponseItem" ui/lib ui/test');
    expect(cardData['status'], 'success');
  });

  test('keeps command output deltas on existing search command card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {
              'id': 'search-cmd-1',
              'type': 'commandExecution',
              'command': 'rg -n "codex/event" ui/lib',
              'status': 'in_progress',
            },
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/commandExecution/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'search-cmd-1',
            'delta': 'ui/lib/services/codex_event_reducer.dart:1\n',
          },
        },
      },
    );

    expect(runtime.messages, hasLength(1));
    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'search');
    expect(cardData['terminalOutput'], contains('codex_event_reducer.dart'));
    expect(cardData['status'], 'running');
  });

  test('maps codex protocol exec command events into terminal cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'codex/event',
        'params': {
          '_meta': {'threadId': 'thread-1'},
          'id': 'event-turn-1',
          'msg': {
            'type': 'exec_command_begin',
            'call_id': 'cmd-1',
            'turn_id': 'turn-1',
            'command': ['flutter', 'test'],
            'cwd': '/repo/ui',
            'parsed_cmd': <dynamic>[],
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'codex/event',
        'params': {
          '_meta': {'threadId': 'thread-1'},
          'id': 'event-turn-1',
          'msg': {
            'type': 'exec_command_output_delta',
            'call_id': 'cmd-1',
            'stream': 'stdout',
            'chunk': base64Encode(utf8.encode('00:01 +1\n')),
          },
        },
      },
    );
    final end = reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'codex/event',
        'params': {
          '_meta': {'threadId': 'thread-1'},
          'id': 'event-turn-1',
          'msg': {
            'type': 'exec_command_end',
            'call_id': 'cmd-1',
            'turn_id': 'turn-1',
            'command': ['flutter', 'test'],
            'cwd': '/repo/ui',
            'parsed_cmd': <dynamic>[],
            'stdout': '00:01 +1\n',
            'stderr': '',
            'aggregated_output': '00:01 +1: All tests passed!\n',
            'exit_code': 0,
            'formatted_output': '00:01 +1: All tests passed!\n',
            'status': 'completed',
          },
        },
      },
    );

    expect(end.handled, isTrue);
    expect(end.threadId, 'thread-1');
    expect(end.turnId, 'turn-1');
    expect(runtime.messages, hasLength(1));
    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolTitle'], 'flutter test');
    expect(cardData['status'], 'success');
    expect(cardData['terminalOutput'], contains('All tests passed'));
  });

  test('maps codex protocol mcp read events into workspace cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'codex/event',
        'params': {
          '_meta': {'threadId': 'thread-1'},
          'id': 'event-turn-1',
          'msg': {
            'type': 'mcp_tool_call_begin',
            'call_id': 'read-1',
            'invocation': {
              'server': 'filesystem',
              'tool': 'read_file',
              'arguments': {'path': 'README.md'},
            },
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'codex/event',
        'params': {
          '_meta': {'threadId': 'thread-1'},
          'id': 'event-turn-1',
          'msg': {
            'type': 'mcp_tool_call_end',
            'call_id': 'read-1',
            'invocation': {
              'server': 'filesystem',
              'tool': 'read_file',
              'arguments': {'path': 'README.md'},
            },
            'result': {
              'Ok': {
                'content': [
                  {'type': 'text', 'text': 'hello'},
                ],
              },
            },
          },
        },
      },
    );

    expect(runtime.messages, hasLength(1));
    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'workspace');
    expect(cardData['toolTitle'], 'Read README.md');
    expect(cardData['status'], 'success');
    expect(cardData['argsJson'], contains('README.md'));
    expect(cardData['rawResultJson'], contains('hello'));
  });

  test('raw function outputs complete and enrich existing tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call',
              'name': 'exec_command',
              'call_id': 'call-cmd-output-1',
              'arguments': jsonEncode({'cmd': 'flutter test'}),
            },
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call_output',
              'call_id': 'call-cmd-output-1',
              'output': '00:01 +1: All tests passed!\n',
            },
          },
        },
      },
    );

    expect(runtime.messages, hasLength(1));
    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolTitle'], 'flutter test');
    expect(cardData['terminalOutput'], contains('All tests passed'));
    expect(cardData['status'], 'success');
  });

  test('raw output-only items still produce visible tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'rawResponseItem/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'item': {
              'type': 'function_call_output',
              'call_id': 'call-output-only-1',
              'output': 'README.md contents',
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'tool');
    expect(cardData['summary'], contains('README.md contents'));
    expect(cardData['rawResultJson'], contains('function_call_output'));
  });

  test('raw response items without ids use stable distinct fallback ids', () {
    for (final query in const ['first query', 'second query']) {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'web_search_call',
                'status': 'completed',
                'action': {'type': 'search', 'query': query},
              },
            },
          },
        },
      );
    }

    expect(runtime.messages, hasLength(2));
    expect(runtime.messages.map((message) => message.id).toSet(), hasLength(2));
    expect(
      runtime.messages.map((message) => message.cardData?['toolTitle']),
      containsAll(<String>['Search: first query', 'Search: second query']),
    );
  });

  test('maps file diffs into first-class diff tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/fileChange/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'file-1',
            'path': 'lib/main.dart',
            'delta': '''
diff --git a/lib/main.dart b/lib/main.dart
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1,2 +1,2 @@
-old line
+new line
 same line
''',
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'file');
    expect(cardData['showDiff'], isTrue);
    expect(cardData['filePath'], 'lib/main.dart');
    expect(cardData['additions'], 1);
    expect(cardData['deletions'], 1);
    expect(cardData['summary'], contains('+1 -1'));
    expect((cardData['diffText'] ?? '').toString(), contains('diff --git'));
  });

  test('maps hunk-only changes json into first-class diff tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/fileChange/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'call-1',
            'type': 'fileChange',
            'id': 'call-1',
            'changes': jsonEncode({
              'path': '/repo/test/services/codex_diff_parser_test.dart',
              'kind': {'type': 'update', 'move_path': null},
              'diff': '''
@@ -1,2 +1,2 @@
-old line
+new line
 same line
''',
            }),
            'status': 'completed',
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'file');
    expect(cardData['toolTitle'], 'Edit codex_diff_parser_test.dart');
    expect(cardData['showDiff'], isTrue);
    expect(
      cardData['filePath'],
      '/repo/test/services/codex_diff_parser_test.dart',
    );
    expect(cardData['changedFiles'], 1);
    expect(cardData['additions'], 1);
    expect(cardData['deletions'], 1);
    expect(cardData['summary'], '1 file · +1 -1');
    expect((cardData['diffText'] ?? '').toString(), contains('diff --git'));
  });

  test('hydrates historical hunk-only file changes as diff cards', () {
    final messages = codexMessagesFromThreadResponseForTesting({
      'thread': {
        'id': 'thread-1',
        'turns': [
          {
            'id': 'turn-1',
            'items': [
              {
                'id': 'call-1',
                'type': 'fileChange',
                'status': 'completed',
                'changes': jsonEncode({
                  'path': '/repo/lib/main.dart',
                  'kind': {'type': 'update'},
                  'diff': '''
@@ -1,2 +1,2 @@
-old line
+new line
 same line
''',
                }),
              },
            ],
          },
        ],
      },
    });

    final cardData = messages.single.cardData!;
    expect(cardData['toolType'], 'file');
    expect(cardData['showDiff'], isTrue);
    expect(cardData['filePath'], '/repo/lib/main.dart');
    expect(cardData['additions'], 1);
    expect(cardData['deletions'], 1);
  });

  test('hydrates historical codex tool item variants as tool cards', () {
    final messages = codexMessagesFromThreadResponseForTesting({
      'thread': {
        'id': 'thread-1',
        'turns': [
          {
            'id': 'turn-1',
            'items': [
              {
                'id': 'search-1',
                'type': 'webSearch',
                'query': 'Codex app server protocol',
                'status': 'completed',
              },
              {
                'id': 'image-1',
                'type': 'imageView',
                'path': '/tmp/screenshot.png',
                'status': 'completed',
              },
              {
                'id': 'tool-1',
                'type': 'mcpToolCall',
                'tool': 'mcp__filesystem__read_file',
                'arguments': '{"path":"README.md"}',
                'status': 'completed',
              },
              {
                'id': 'sdk-read-1',
                'type': 'mcp_tool_call',
                'server': 'filesystem',
                'tool': 'read_file',
                'arguments': {'path': 'AGENTS.md'},
                'status': 'completed',
              },
              {
                'id': 'sdk-cmd-1',
                'type': 'command_execution',
                'command': 'flutter test',
                'aggregated_output': '00:01 +1: All tests passed!',
                'exit_code': 0,
                'status': 'completed',
              },
              {
                'type': 'function_call',
                'name': 'read_file',
                'call_id': 'raw-read-1',
                'arguments': '{"path":"lib/main.dart"}',
              },
              {
                'type': 'local_shell_call',
                'call_id': 'raw-shell-1',
                'status': 'completed',
                'action': {
                  'type': 'exec',
                  'command': ['git', 'status'],
                },
              },
            ],
          },
        ],
      },
    });

    final cards = messages.map((message) => message.cardData!).toList();
    expect(
      cards.map((card) => card['toolType']),
      containsAll(<String>['search', 'image', 'workspace', 'terminal']),
    );
    expect(
      cards.map((card) => card['toolTitle']),
      containsAll(<String>[
        'Search: Codex app server protocol',
        'View screenshot.png',
        'Read README.md',
        'Read AGENTS.md',
        'flutter test',
        'Read main.dart',
        'git status',
      ]),
    );
  });

  test('hydrates historical raw function outputs onto matching tool card', () {
    final messages = codexMessagesFromThreadResponseForTesting({
      'thread': {
        'id': 'thread-1',
        'turns': [
          {
            'id': 'turn-1',
            'items': [
              {
                'type': 'function_call',
                'name': 'exec_command',
                'call_id': 'raw-cmd-1',
                'arguments': '{"cmd":"flutter test"}',
              },
              {
                'type': 'function_call_output',
                'call_id': 'raw-cmd-1',
                'output': '00:01 +1: All tests passed!',
              },
            ],
          },
        ],
      },
    });

    expect(messages, hasLength(1));
    final cardData = messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['toolTitle'], 'flutter test');
    expect(cardData['terminalOutput'], contains('All tests passed'));
    expect(cardData['summary'], contains('All tests passed'));
  });

  test(
    'hydrates historical codex protocol command events as one tool card',
    () {
      final messages = codexMessagesFromThreadResponseForTesting({
        'thread': {
          'id': 'thread-1',
          'turns': [
            {
              'id': 'turn-1',
              'events': [
                {
                  'method': 'codex/event',
                  'params': {
                    '_meta': {'threadId': 'thread-1'},
                    'id': 'event-turn-1',
                    'msg': {
                      'type': 'exec_command_begin',
                      'call_id': 'cmd-1',
                      'turn_id': 'turn-1',
                      'command': ['flutter', 'test'],
                      'cwd': '/repo/ui',
                      'parsed_cmd': <dynamic>[],
                    },
                  },
                },
                {
                  'method': 'codex/event',
                  'params': {
                    '_meta': {'threadId': 'thread-1'},
                    'id': 'event-turn-1',
                    'msg': {
                      'type': 'exec_command_output_delta',
                      'call_id': 'cmd-1',
                      'stream': 'stdout',
                      'chunk': base64Encode(utf8.encode('00:01 +1\n')),
                    },
                  },
                },
                {
                  'method': 'codex/event',
                  'params': {
                    '_meta': {'threadId': 'thread-1'},
                    'id': 'event-turn-1',
                    'msg': {
                      'type': 'exec_command_end',
                      'call_id': 'cmd-1',
                      'turn_id': 'turn-1',
                      'command': ['flutter', 'test'],
                      'cwd': '/repo/ui',
                      'parsed_cmd': <dynamic>[],
                      'stdout': '00:01 +1\n',
                      'stderr': '',
                      'aggregated_output': '00:01 +1: All tests passed!\n',
                      'exit_code': 0,
                      'status': 'completed',
                    },
                  },
                },
              ],
            },
          ],
        },
      });

      expect(messages, hasLength(1));
      final cardData = messages.single.cardData!;
      expect(cardData['toolType'], 'terminal');
      expect(cardData['toolTitle'], 'flutter test');
      expect(cardData['terminalOutput'], contains('All tests passed'));
      expect(cardData['status'], 'success');
    },
  );

  test('hydrates historical codex protocol mcp read events', () {
    final messages = codexMessagesFromThreadResponseForTesting({
      'thread': {
        'id': 'thread-1',
        'turns': [
          {
            'id': 'turn-1',
            'events': [
              {
                'method': 'codex/event',
                'params': {
                  '_meta': {'threadId': 'thread-1'},
                  'id': 'event-turn-1',
                  'msg': {
                    'type': 'mcp_tool_call_begin',
                    'call_id': 'read-1',
                    'invocation': {
                      'server': 'filesystem',
                      'tool': 'read_file',
                      'arguments': {'path': 'README.md'},
                    },
                  },
                },
              },
              {
                'method': 'codex/event',
                'params': {
                  '_meta': {'threadId': 'thread-1'},
                  'id': 'event-turn-1',
                  'msg': {
                    'type': 'mcp_tool_call_end',
                    'call_id': 'read-1',
                    'invocation': {
                      'server': 'filesystem',
                      'tool': 'read_file',
                      'arguments': {'path': 'README.md'},
                    },
                    'result': {
                      'Ok': {
                        'content': [
                          {'type': 'text', 'text': 'hello'},
                        ],
                      },
                    },
                  },
                },
              },
            ],
          },
        ],
      },
    });

    expect(messages, hasLength(1));
    final cardData = messages.single.cardData!;
    expect(cardData['toolType'], 'workspace');
    expect(cardData['toolTitle'], 'Read README.md');
    expect(cardData['status'], 'success');
    expect(cardData['rawResultJson'], contains('hello'));
  });

  test('hydrates codex user image blocks as message attachments', () {
    final messages = codexMessagesFromThreadResponseForTesting({
      'thread': {
        'id': 'thread-1',
        'turns': [
          {
            'id': 'turn-1',
            'items': [
              {
                'id': 'user-1',
                'type': 'userMessage',
                'content': [
                  {'type': 'text', 'text': '看这张图'},
                  {
                    'type': 'image',
                    'detail': null,
                    'url': 'data:image/png;base64,AAAA',
                  },
                ],
              },
            ],
          },
        ],
      },
    });

    final message = messages.single;
    expect(message.user, 1);
    expect(message.text, '看这张图');
    expect(message.text, isNot(contains('data:image')));
    expect(message.text, isNot(contains('{type: image')));

    final attachments = message.content?['attachments'] as List;
    expect(attachments, hasLength(1));
    final attachment = attachments.single as Map<String, dynamic>;
    expect(attachment['dataUrl'], 'data:image/png;base64,AAAA');
    expect(attachment['mimeType'], 'image/png');
    expect(attachment['isImage'], isTrue);
  });

  test('uses file paths for concise file change tool titles', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {
              'id': 'file-1',
              'type': 'fileChange',
              'path': '/repo/lib/main.dart',
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolTitle'], 'Edit main.dart');
  });

  test('uses generic tool params for concise tool titles', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {
              'id': 'tool-1',
              'type': 'tool',
              'toolName': 'mcp__context7__query_docs',
              'arguments': '{"query":"Riverpod provider override"}',
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolTitle'], 'query_docs: Riverpod provider override');
  });

  test('maps mcp read file calls into workspace tool cards', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {
              'id': 'tool-1',
              'type': 'mcpToolCall',
              'tool': 'mcp__filesystem__read_file',
              'arguments': '{"path":"README.md"}',
            },
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'agent_tool_summary');
    expect(cardData['toolType'], 'workspace');
    expect(cardData['toolTitle'], 'Read README.md');
    expect(cardData['argsJson'], contains('README.md'));
  });

  test(
    'maps sdk command_execution events without method into terminal cards',
    () {
      final started = reducer.reduce(
        runtime: runtime,
        event: {
          'type': 'item.started',
          'thread_id': 'thread-1',
          'turn_id': 'turn-1',
          'item': {
            'id': 'cmd-1',
            'type': 'command_execution',
            'command': 'cd ui && flutter test',
            'aggregated_output': '',
            'status': 'in_progress',
          },
        },
      );

      expect(started.handled, isTrue);
      var cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolType'], 'terminal');
      expect(cardData['toolTitle'], 'cd ui && flutter test');
      expect(cardData['status'], 'running');

      reducer.reduce(
        runtime: runtime,
        event: {
          'type': 'item.completed',
          'thread_id': 'thread-1',
          'turn_id': 'turn-1',
          'item': {
            'id': 'cmd-1',
            'type': 'command_execution',
            'command': 'cd ui && flutter test',
            'aggregated_output': '00:01 +1: All tests passed!\n',
            'exit_code': 0,
            'status': 'completed',
          },
        },
      );

      cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'terminal');
      expect(cardData['status'], 'success');
      expect(cardData['terminalOutput'], contains('All tests passed'));
    },
  );

  test(
    'maps sdk mcp_tool_call read events without method into workspace cards',
    () {
      final result = reducer.reduce(
        runtime: runtime,
        event: {
          'type': 'item.completed',
          'thread_id': 'thread-1',
          'turn_id': 'turn-1',
          'item': {
            'id': 'read-1',
            'type': 'mcp_tool_call',
            'server': 'filesystem',
            'tool': 'read_file',
            'arguments': {'path': 'README.md'},
            'status': 'completed',
          },
        },
      );

      expect(result.handled, isTrue);
      final cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolType'], 'workspace');
      expect(cardData['toolTitle'], 'Read README.md');
      expect(cardData['argsJson'], contains('README.md'));
    },
  );

  test('completed command snapshots update terminal output and status', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'npm test',
            },
          },
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/completed',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'cmd-1',
            'item': {
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'npm test',
              'aggregatedOutput': 'test failed\n',
              'exitCode': 1,
            },
          },
        },
      },
    );

    expect(runtime.messages, hasLength(1));
    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'terminal');
    expect(cardData['status'], 'error');
    expect(cardData['terminalOutput'], 'test failed\n');
  });

  test('patch updated events keep file diff cards current', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/fileChange/patchUpdated',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'file-1',
            'changes': jsonEncode({
              'path': '/repo/lib/app.dart',
              'kind': {'type': 'update'},
              'diff': '''
@@ -1 +1 @@
-old
+new
''',
            }),
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['toolType'], 'file');
    expect(cardData['showDiff'], isTrue);
    expect(cardData['filePath'], '/repo/lib/app.dart');
    expect(cardData['summary'], '1 file · +1 -1');
  });

  test('keeps agent message entries separate by codex item id', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': 'first'},
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'itemId': 'msg-2', 'delta': 'second'},
        },
      },
    );

    expect(runtime.messages.map((message) => message.id).toList(), <String>[
      'msg-2-codex-agent',
      'msg-1-codex-agent',
    ]);
    expect(runtime.messages.first.streamMeta?['parentTaskId'], 'turn-1');
    expect(runtime.messages.first.streamMeta?['entryId'], 'msg-2-codex-agent');
    expect(runtime.messages.first.streamMeta?['seq'], 2);
    expect(runtime.messages.last.streamMeta?['seq'], 1);
  });

  test('marks thread active from object status payload', () {
    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'thread/status/changed',
          'params': {
            'threadId': 'thread-1',
            'status': {'type': 'active', 'activeFlags': <dynamic>[]},
          },
        },
      },
    );

    expect(result.handled, isTrue);
    expect(runtime.isAiResponding, isTrue);
  });

  test('marks upstream turn started notification as processing', () {
    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'method': 'turn/started',
        'params': {
          'threadId': 'thread-1',
          'turn': {'id': 'turn-1', 'status': 'inProgress'},
        },
      },
    );

    expect(result.handled, isTrue);
    expect(result.threadId, 'thread-1');
    expect(result.turnId, 'turn-1');
    expect(runtime.isAiResponding, isTrue);
    expect(runtime.currentDispatchTaskId, 'turn-1');
  });

  test(
    'renders latest snapshot reasoning as active without explicit turn id',
    () {
      final messages = codexMessagesFromThreadResponseForTesting({
        'thread': {
          'id': 'thread-1',
          'status': {'type': 'active', 'activeFlags': <dynamic>[]},
          'turns': [
            {
              'id': 'turn-1',
              'status': 'inProgress',
              'items': [
                {
                  'id': 'user-1',
                  'type': 'userMessage',
                  'content': [
                    {'text': 'hi'},
                  ],
                },
                {
                  'id': 'reasoning-1',
                  'type': 'reasoning',
                  'summary': ['thinking'],
                  'content': <dynamic>[],
                },
              ],
            },
          ],
        },
      }, active: true);

      final cardData = messages.first.cardData!;
      expect(cardData['type'], 'deep_thinking');
      expect(cardData['isLoading'], isTrue);
      expect(cardData['stage'], ThinkingStage.thinking.value);
      expect(cardData['isCollapsible'], isFalse);
      expect(messages.first.streamMeta?['isFinal'], isFalse);
    },
  );

  test('detects stale-normalized remote active turn shape', () {
    final looksActive = codexLatestTurnLooksExternallyActiveForTesting({
      'thread': {
        'id': 'thread-1',
        'status': {'type': 'idle'},
        'turns': [
          {
            'id': 'turn-1',
            'status': 'interrupted',
            'completedAt': null,
            'items': [
              {
                'id': 'reasoning-1',
                'type': 'reasoning',
                'summary': ['still writing'],
              },
            ],
          },
        ],
      },
    });

    expect(looksActive, isTrue);
  });

  test('marks thread idle from object status payload', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'thread/status/changed',
          'params': {
            'threadId': 'thread-1',
            'status': {'type': 'active'},
          },
        },
      },
    );

    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'thread/status/changed',
          'params': {
            'threadId': 'thread-1',
            'status': {'type': 'idle'},
          },
        },
      },
    );

    expect(result.handled, isTrue);
    expect(runtime.isAiResponding, isFalse);
  });

  test('thread idle finalizes active turn without cancellation body', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/started',
          'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'thinking',
          },
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'thread/status/changed',
          'params': {
            'threadId': 'thread-1',
            'status': {'type': 'idle'},
          },
        },
      },
    );

    expect(runtime.isAiResponding, isFalse);
    expect(runtime.currentDispatchTaskId, isNull);
    expect(
      runtime.messages.any((message) => message.id.endsWith('cancelled')),
      isFalse,
    );
    expect(runtime.messages.single.cardData!['isLoading'], isFalse);
  });

  test('ignores replayed assistant deltas after snapshot hydration', () {
    runtime.messages.add(
      ChatMessageModel(
        id: 'msg-1-codex-agent',
        type: 1,
        user: 2,
        content: {'text': 'Hello', 'id': 'msg-1-codex-agent'},
      ),
    );

    for (final delta in const ['Hel', 'lo', '!']) {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/agentMessage/delta',
            'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': delta},
          },
        },
      );
    }

    expect(runtime.messages.single.text, 'Hello!');
  });

  test('replayed assistant deltas do not restart an idle turn', () {
    runtime.messages.add(
      ChatMessageModel(
        id: 'msg-1-codex-agent',
        type: 1,
        user: 2,
        content: {'text': 'Hello', 'id': 'msg-1-codex-agent'},
      ),
    );

    for (final delta in const ['Hel', 'lo']) {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/agentMessage/delta',
            'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': delta},
          },
        },
      );
    }

    expect(runtime.messages.single.text, 'Hello');
    expect(runtime.isAiResponding, isFalse);
    expect(runtime.currentDispatchTaskId, isNull);
    expect(runtime.currentAiMessages, isEmpty);
  });

  test('idle status does not clear partial replay delta offsets', () {
    runtime.messages.add(
      ChatMessageModel(
        id: 'msg-1-codex-agent',
        type: 1,
        user: 2,
        content: {'text': 'Hello', 'id': 'msg-1-codex-agent'},
      ),
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': 'Hel'},
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'thread/status/changed',
          'params': {
            'threadId': 'thread-1',
            'status': {'type': 'idle'},
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': 'lo'},
        },
      },
    );

    expect(runtime.messages.single.text, 'Hello');
    expect(runtime.isAiResponding, isFalse);
    expect(runtime.currentDispatchTaskId, isNull);
  });

  test('keeps replay delta offsets across matching snapshot replacement', () {
    final coordinator = ChatConversationRuntimeCoordinator.instance;
    const conversationId = 420042;
    final hydratedMessage = ChatMessageModel(
      id: 'msg-1-codex-agent',
      type: 1,
      user: 2,
      content: {'text': 'Hello', 'id': 'msg-1-codex-agent'},
    );
    final coordinatorRuntime = coordinator.ensureRuntime(
      conversationId: conversationId,
      mode: kChatRuntimeModeCodex,
      initialMessages: [hydratedMessage],
    );
    coordinatorRuntime.codexReplayDeltaOffsets['msg-1-codex-agent'] = 3;
    coordinatorRuntime.codexReplayDeltaOffsets['stale-entry'] = 2;

    coordinator.replaceConversationSnapshot(
      conversationId: conversationId,
      mode: kChatRuntimeModeCodex,
      messages: [hydratedMessage],
    );

    final updatedRuntime = coordinator.runtimeFor(
      conversationId: conversationId,
      mode: kChatRuntimeModeCodex,
    )!;
    expect(updatedRuntime.codexReplayDeltaOffsets['msg-1-codex-agent'], 3);
    expect(
      updatedRuntime.codexReplayDeltaOffsets.containsKey('stale-entry'),
      isFalse,
    );
  });

  test(
    'preserves extra local duplicate user messages missing from snapshot',
    () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final merged = mergeRemoteCodexSnapshotMessagesForTesting(
        snapshotMessages: [
          ChatMessageModel(
            id: 'remote-user-1',
            type: 1,
            user: 1,
            content: {'text': 'again', 'id': 'remote-user-1'},
            createAt: now,
          ),
        ],
        existingMessages: [
          ChatMessageModel(
            id: 'local-user-2',
            type: 1,
            user: 1,
            content: {'text': 'again', 'id': 'local-user-2'},
            createAt: now.add(const Duration(seconds: 2)),
          ),
          ChatMessageModel(
            id: 'local-user-1',
            type: 1,
            user: 1,
            content: {'text': 'again', 'id': 'local-user-1'},
            createAt: now.add(const Duration(seconds: 1)),
          ),
        ],
        activeTaskId: null,
        isAiResponding: false,
      );

      expect(merged.map((message) => message.id), contains('remote-user-1'));
      expect(merged.map((message) => message.id), contains('local-user-2'));
      expect(
        merged.map((message) => message.id),
        isNot(contains('local-user-1')),
      );
    },
  );

  test('finalizes assistant item without duplicating completed text', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/agentMessage/delta',
          'params': {'turnId': 'turn-1', 'itemId': 'msg-1', 'delta': 'Hel'},
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/completed',
          'params': {
            'turnId': 'turn-1',
            'item': {'id': 'msg-1', 'type': 'agentMessage', 'text': 'Hello'},
          },
        },
      },
    );

    expect(runtime.messages.single.text, 'Hello');
    expect(runtime.messages.single.streamMeta?['isFinal'], isTrue);
    expect(runtime.currentAiMessages, isEmpty);
  });

  test('keeps reasoning timer stable across deltas and completion', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/started',
          'params': {
            'turnId': 'turn-1',
            'item': {'id': 'reason-1', 'type': 'reasoning'},
          },
        },
      },
    );

    final startedCard = runtime.messages.single;
    final startedStartTime = startedCard.cardData!['startTime'];

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'thinking',
          },
        },
      },
    );

    expect(runtime.messages.single.id, 'reason-1-codex-thinking');
    expect(runtime.messages.single.cardData!['startTime'], startedStartTime);
    expect(runtime.messages.single.cardData!['thinkingContent'], 'thinking');

    // item/completed for reasoning no longer flips the card to complete — the
    // turn may still emit more reasoning, tool calls, or an agent message.
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/completed',
          'params': {
            'turnId': 'turn-1',
            'item': {'id': 'reason-1', 'type': 'reasoning'},
          },
        },
      },
    );
    final midTurnCard = runtime.messages.single.cardData!;
    expect(midTurnCard['startTime'], startedStartTime);
    expect(midTurnCard['isLoading'], isTrue);
    expect(midTurnCard['stage'], ThinkingStage.thinking.value);

    // turn/completed is the terminal signal that finalizes the thinking card.
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/completed',
          'params': {'turnId': 'turn-1'},
        },
      },
    );

    final completedCard = runtime.messages
        .firstWhere((message) => message.cardData?['type'] == 'deep_thinking')
        .cardData!;
    expect(completedCard['startTime'], startedStartTime);
    expect(completedCard['stage'], ThinkingStage.complete.value);
    expect(completedCard['isLoading'], isFalse);
    expect(completedCard['endTime'], isNotNull);
  });

  test('turn completion after manual interrupt leaves a cancellation body', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/started',
          'params': {'turnId': 'turn-1'},
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'thinking',
          },
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/completed',
          'params': {'turnId': 'turn-1'},
        },
      },
    );

    final cancelMessage = runtime.messages.firstWhere(
      (message) => message.id == 'turn-1-cancelled',
    );
    expect(cancelMessage.text, '任务已取消');
    expect(cancelMessage.streamMeta?['parentTaskId'], 'turn-1');
    expect(cancelMessage.streamMeta?['isFinal'], isTrue);
  });

  test('updates tool cards in place with stable codex stream metadata', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/commandExecution/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'cmd-1',
            'command': 'ls',
            'delta': 'a\n',
          },
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/commandExecution/outputDelta',
          'params': {
            'turnId': 'turn-1',
            'itemId': 'cmd-1',
            'command': 'ls',
            'delta': 'b\n',
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['terminalOutput'], 'a\nb\n');
    expect(
      runtime.messages.single.streamMeta?['entryId'],
      'cmd-1-codex-command',
    );
    expect(runtime.messages.single.streamMeta?['seq'], 1);
  });

  test('maps approval requests into codex request card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'id': 7,
          'method': 'item/commandExecution/requestApproval',
          'params': {'command': 'rm tmp.txt', 'reason': 'cleanup'},
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'codex_request');
    expect(cardData['requestKind'], 'approval');
    expect(cardData['requestId'], 7);
  });

  test('maps request user input into codex request card', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'id': 'request-1',
          'method': 'item/tool/requestUserInput',
          'params': {
            'questions': [
              {'id': 'choice', 'question': 'Choose one'},
            ],
          },
        },
      },
    );

    final cardData = runtime.messages.single.cardData!;
    expect(cardData['type'], 'codex_request');
    expect(cardData['requestKind'], 'user_input');
    expect(cardData['questionId'], 'choice');
  });

  test('ignores unknown events without throwing', () {
    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'future/event',
          'params': {'raw': true},
        },
      },
    );

    expect(result.handled, isFalse);
    expect(runtime.messages, isEmpty);
  });

  test('ignores codex stderr logs without creating tool cards', () {
    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'codex/stderr',
          'params': {'message': 'startup log'},
        },
      },
    );

    expect(result.handled, isFalse);
    expect(runtime.messages, isEmpty);
  });

  test('removes stale codex stderr status cards', () {
    runtime.messages.add(
      ChatMessageModel.cardMessage({
        'type': 'agent_tool_summary',
        'toolName': 'codex.status',
        'toolTitle': 'codex/stderr',
        'displayName': 'codex/stderr',
        'status': 'running',
      }, id: 'stderr-status'),
    );

    final result = reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'codex/stderr',
          'params': {'message': 'startup log'},
        },
      },
    );

    expect(result.handled, isTrue);
    expect(runtime.messages, isEmpty);
  });

  test(
    'reasoning item/completed during active turn keeps thinking card loading',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'turn/started',
            'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/reasoning/textDelta',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'itemId': 'reason-1',
              'delta': 'analysing the request',
            },
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'itemId': 'reason-1',
              'item': {
                'id': 'reason-1',
                'type': 'reasoning',
                'summary': 'analysing the request',
              },
            },
          },
        },
      );

      final card = runtime.messages.firstWhere(
        (message) => message.cardData?['type'] == 'deep_thinking',
      );
      final cardData = card.cardData!;
      expect(cardData['isLoading'], isTrue);
      expect(cardData['isCollapsible'], isFalse);
      expect(cardData['stage'], ThinkingStage.thinking.value);
      expect(runtime.isAiResponding, isTrue);
    },
  );

  test('turn/completed finalizes the thinking card after reasoning ends', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/started',
          'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'finished thinking',
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'item': {
              'id': 'reason-1',
              'type': 'reasoning',
              'summary': 'finished thinking',
            },
          },
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/completed',
          'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
        },
      },
    );

    final card = runtime.messages.firstWhere(
      (message) => message.cardData?['type'] == 'deep_thinking',
    );
    final cardData = card.cardData!;
    expect(cardData['isLoading'], isFalse);
    expect(cardData['isCollapsible'], isTrue);
    expect(cardData['stage'], ThinkingStage.complete.value);
    expect(runtime.isAiResponding, isFalse);
  });

  test('top-level error with willRetry=false finalizes the active turn', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/started',
          'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
        },
      },
    );
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'item/reasoning/textDelta',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'reason-1',
            'delta': 'thinking',
          },
        },
      },
    );

    expect(runtime.isAiResponding, isTrue);

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'error',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'willRetry': false,
            'message': 'connection lost',
          },
        },
      },
    );

    expect(runtime.isAiResponding, isFalse);
    expect(runtime.currentDispatchTaskId, isNull);
    final thinking = runtime.messages
        .firstWhere((message) => message.cardData?['type'] == 'deep_thinking')
        .cardData!;
    expect(thinking['isLoading'], isFalse);
    expect(thinking['stage'], ThinkingStage.complete.value);
  });

  test('top-level error with willRetry=true keeps the turn active', () {
    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'turn/started',
          'params': {'threadId': 'thread-1', 'turnId': 'turn-1'},
        },
      },
    );

    reducer.reduce(
      runtime: runtime,
      event: {
        'message': {
          'method': 'error',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'willRetry': true,
            'message': 'rate limited',
          },
        },
      },
    );

    expect(runtime.isAiResponding, isTrue);
    expect(runtime.currentDispatchTaskId, isNotNull);
  });

  test(
    'snapshot renders reasoning as loading even when item.status is completed '
    'while turn is active',
    () {
      final messages = codexMessagesFromThreadResponseForTesting(
        {
          'thread': {
            'id': 'thread-1',
            'status': {'type': 'active'},
            'turns': [
              {
                'id': 'turn-1',
                'status': 'inProgress',
                'items': [
                  {
                    'id': 'reason-1',
                    'type': 'reasoning',
                    'status': 'completed',
                    'summary': ['done reasoning'],
                  },
                ],
              },
            ],
          },
        },
        active: true,
        activeTurnId: 'turn-1',
      );

      final cardData = messages.first.cardData!;
      expect(cardData['type'], 'deep_thinking');
      expect(cardData['isLoading'], isTrue);
      expect(cardData['isCollapsible'], isFalse);
      expect(cardData['stage'], ThinkingStage.thinking.value);
    },
  );

  test(
    'codex protocol exec_command_begin with parsed_cmd read renders as workspace card',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'exec_command_begin',
              'call_id': 'read-1',
              'turn_id': 'turn-1',
              'command': ['cat', 'README.md'],
              'cwd': '/repo',
              'parsed_cmd': <Map<String, dynamic>>[
                {
                  'type': 'read',
                  'cmd': 'cat README.md',
                  'name': 'README.md',
                  'path': 'README.md',
                },
              ],
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolType'], 'workspace');
      expect(cardData['toolTitle'], 'Read README.md');
      expect(cardData['status'], 'running');
    },
  );

  test(
    'item/started commandExecution with commandActions read uses workspace card and keeps deltas',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/started',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'read-2',
                'type': 'commandExecution',
                'command': 'sed -n 1,200p AGENTS.md',
                'cwd': '/repo',
                'status': 'in_progress',
                'commandActions': <Map<String, dynamic>>[
                  {
                    'type': 'read',
                    'command': 'sed -n 1,200p AGENTS.md',
                    'name': 'AGENTS.md',
                    'path': '/repo/AGENTS.md',
                  },
                ],
              },
            },
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/commandExecution/outputDelta',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'itemId': 'read-2',
              'delta': '# Project AGENTS.md\n',
            },
          },
        },
      );

      expect(runtime.messages, hasLength(1));
      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'workspace');
      expect(cardData['toolTitle'], 'Read AGENTS.md');
      expect(cardData['terminalOutput'], contains('Project AGENTS.md'));
      expect(cardData['status'], 'running');
    },
  );

  test(
    'parsed_cmd search at exec_command_begin classifies card as search before output',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'exec_command_begin',
              'call_id': 'search-1',
              'turn_id': 'turn-1',
              'command': ['rg', '-n', 'parsed_cmd', 'ui/lib'],
              'cwd': '/repo',
              'parsed_cmd': <Map<String, dynamic>>[
                {
                  'type': 'search',
                  'cmd': 'rg -n parsed_cmd ui/lib',
                  'query': 'parsed_cmd',
                  'path': 'ui/lib',
                },
              ],
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'search');
      expect(cardData['toolTitle'], 'Search: parsed_cmd');
      expect(cardData['status'], 'running');
    },
  );

  test(
    'parsed_cmd list_files at item/started becomes workspace List card',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/started',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'list-1',
                'type': 'commandExecution',
                'command': 'ls /repo/ui',
                'cwd': '/repo',
                'status': 'in_progress',
                'commandActions': <Map<String, dynamic>>[
                  {
                    'type': 'listFiles',
                    'command': 'ls /repo/ui',
                    'path': '/repo/ui',
                  },
                ],
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'workspace');
      expect(cardData['toolTitle'], 'List ui');
    },
  );

  test(
    'parsed_cmd unknown falls back to terminal classification',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'exec_command_begin',
              'call_id': 'cmd-x',
              'turn_id': 'turn-1',
              'command': ['git', 'status'],
              'cwd': '/repo',
              'parsed_cmd': <Map<String, dynamic>>[
                {'type': 'unknown', 'cmd': 'git status'},
              ],
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'terminal');
      expect(cardData['toolTitle'], 'git status');
    },
  );

  test(
    'mcp_tool_call_end with arguments.title shows title instead of tool name',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'mcp_tool_call_end',
              'call_id': 'call_agQUhiEvZgvXKxX7ursGybbn',
              'invocation': {
                'server': 'node_repl',
                'tool': 'js',
                'arguments': {
                  'title': 'Refine flavor parsing',
                  'code': "nodeRepl.write('ok');",
                },
              },
              'result': {
                'Ok': {
                  'content': [
                    {'type': 'text', 'text': '{"ok":true}'},
                  ],
                },
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolTitle'], 'Refine flavor parsing');
      expect(cardData['status'], 'success');
    },
  );

  test(
    'mcp_tool_call_begin streams running card with --title argument as title',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'mcp_tool_call_begin',
              'call_id': 'call_running_js',
              'invocation': {
                'server': 'node_repl',
                'tool': 'js',
                'arguments': {
                  'title': 'Read-only project metadata parse',
                  'code': '/* long js */',
                },
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolTitle'], 'Read-only project metadata parse');
      expect(cardData['status'], 'running');
    },
  );

  test(
    'rawResponseItem function_call js with arguments.title shows title',
    () {
      // Mirrors the OpenAI Responses path: codex app-server forwards
      // EVERY function_call ResponseItem as rawResponseItem/completed. For
      // node_repl/js the arguments JSON carries a human-readable title
      // alongside the code blob.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'js',
                'call_id': 'call_agQUhiEvZgvXKxX7ursGybbn',
                'arguments': jsonEncode({
                  'title': 'Refine flavor parsing',
                  'code': "const fs2 = await import('node:fs/promises');",
                }),
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolTitle'], 'Refine flavor parsing');
    },
  );

  test(
    'rawResponseItem then mcp_tool_call_end for same call_id collapse to one card',
    () {
      // Realistic order: function_call rawResponseItem fires first, then the
      // projected mcp_tool_call_end. They share the same call_id, so the
      // second event should update the SAME card rather than spawn a second.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'js',
                'call_id': 'call_shared_1',
                'arguments': jsonEncode({
                  'title': 'Read-only project metadata parse',
                  'code': '/* … */',
                }),
              },
            },
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {'threadId': 'thread-1'},
            'id': 'event-turn-1',
            'msg': {
              'type': 'mcp_tool_call_end',
              'call_id': 'call_shared_1',
              'invocation': {
                'server': 'node_repl',
                'tool': 'js',
                'arguments': {
                  'title': 'Read-only project metadata parse',
                  'code': '/* … */',
                },
              },
              'result': {
                'Ok': {
                  'content': [
                    {'type': 'text', 'text': '{"ok":true}'},
                  ],
                },
              },
            },
          },
        },
      );

      expect(runtime.messages, hasLength(1));
      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolTitle'], 'Read-only project metadata parse');
      expect(cardData['status'], 'success');
    },
  );

  test(
    'rawResponseItem function_call exec_command shows the cmd as title',
    () {
      // exec_command is the dominant tool in the user-reported session
      // (22 occurrences). Arguments JSON has {cmd, workdir, max_output_tokens}.
      // The card should be a terminal-type card titled with the cmd.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'exec_command',
                'call_id': 'call_5qvsAWrt1UCjXkfPlakIsqXD',
                'arguments': jsonEncode({
                  'cmd': "sed -n '1,260p' app/build.gradle.kts",
                  'workdir': '/Users/ocean/code/OmnibotApp',
                  'max_output_tokens': 16000,
                }),
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['type'], 'agent_tool_summary');
      expect(cardData['toolType'], 'terminal');
      expect(
        cardData['toolTitle'],
        contains("sed -n '1,260p' app/build.gradle.kts"),
      );
    },
  );

  test(
    'function_call_output for exec_command merges output into the same card',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'exec_command',
                'call_id': 'call_merge_1',
                'arguments': jsonEncode({
                  'cmd': 'pwd',
                  'workdir': '/repo',
                  'max_output_tokens': 2000,
                }),
              },
            },
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call_output',
                'call_id': 'call_merge_1',
                'output': '/repo\n',
              },
            },
          },
        },
      );

      expect(runtime.messages, hasLength(1));
      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolType'], 'terminal');
      expect(cardData['toolTitle'], 'pwd');
      expect(cardData['terminalOutput'], contains('/repo'));
      expect(cardData['status'], 'success');
    },
  );

  test(
    'replays the user-reported exec_command turn (19 function_calls + 1 mcp)',
    () {
      // Replays the actual session 019e7ca6-bb65-7d43-822f-b7eb78cc3033:
      // 18 exec_command function_calls + 1 js function_call + 1
      // load_workspace_dependencies function_call + 1 mcp_tool_call_end.
      // The user reported that only the MCP card showed up. This test
      // exercises every event-router path the codex app-server WOULD have
      // emitted for that turn (turn/started, rawResponseItem/completed for
      // each function_call, item/started+commandExecution variant, mcp end)
      // and asserts the runtime ends up with one card per call_id.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'turn/started',
            'params': {
              'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
              'turnId': 'turn-1',
            },
          },
        },
      );

      const execCommands = <String>[
        'pwd',
        'git status --short --branch',
        "rg --files -g '!*build*' | sed -n '1,80p'",
        "find . -maxdepth 2 -type d | sort | sed -n '1,80p'",
        'rg -n "include\\(|pluginManagement" settings.gradle.kts',
        "sed -n '1,260p' app/build.gradle.kts",
        "sed -n '1,220p' ui/pubspec.yaml",
        "sed -n '1,220p' assists/build.gradle.kts",
        "sed -n '1,220p' baselib/build.gradle.kts",
        "rg -n 'class App' app/src/main",
        "sed -n '1,80p' AGENTS.md",
        "rg --files app/src | sed -n '1,40p'",
        'git branch --show-current',
        'git log --oneline -5',
        "cat README.md | head -30",
        "ls -la",
        "wc -l ui/pubspec.yaml",
        "git diff --stat",
      ];

      for (var index = 0; index < execCommands.length; index += 1) {
        reducer.reduce(
          runtime: runtime,
          event: {
            'message': {
              'method': 'rawResponseItem/completed',
              'params': {
                'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
                'turnId': 'turn-1',
                'item': {
                  'type': 'function_call',
                  'name': 'exec_command',
                  'call_id': 'call_exec_$index',
                  'arguments': jsonEncode({
                    'cmd': execCommands[index],
                    'workdir': '/Users/ocean/code/OmnibotApp',
                    'yield_time_ms': 1000,
                    'max_output_tokens': 2000,
                  }),
                },
              },
            },
          },
        );
        // function_call_output (the actual exec result) comes right after.
        reducer.reduce(
          runtime: runtime,
          event: {
            'message': {
              'method': 'rawResponseItem/completed',
              'params': {
                'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
                'turnId': 'turn-1',
                'item': {
                  'type': 'function_call_output',
                  'call_id': 'call_exec_$index',
                  'output': '(output ${execCommands[index]})\n',
                },
              },
            },
          },
        );
      }

      // The single js function_call + mcp_tool_call_end pair.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'js',
                'call_id': 'call_js_1',
                'arguments': jsonEncode({
                  'title': 'Inspect modules and dependencies',
                  'code': '/* js code … */',
                }),
              },
            },
          },
        },
      );
      reducer.reduce(
        runtime: runtime,
        event: {
          'method': 'codex/event',
          'params': {
            '_meta': {
              'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
            },
            'id': 'mcp-1',
            'msg': {
              'type': 'mcp_tool_call_end',
              'call_id': 'call_js_1',
              'invocation': {
                'server': 'node_repl',
                'tool': 'js',
                'arguments': {
                  'title': 'Inspect modules and dependencies',
                  'code': '/* js code … */',
                },
              },
              'result': {
                'Ok': {
                  'content': [
                    {'type': 'text', 'text': '{"ok":true}'},
                  ],
                },
              },
            },
          },
        },
      );

      // load_workspace_dependencies is a codex_app namespace function_call.
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'rawResponseItem/completed',
            'params': {
              'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
              'turnId': 'turn-1',
              'item': {
                'type': 'function_call',
                'name': 'load_workspace_dependencies',
                'namespace': 'codex_app',
                'call_id': 'call_lwd_1',
                'arguments': '{}',
              },
            },
          },
        },
      );

      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'turn/completed',
            'params': {
              'threadId': '019e7ca6-bb65-7d43-822f-b7eb78cc3033',
              'turnId': 'turn-1',
            },
          },
        },
      );

      // Expectation:
      //   18 unique exec_command cards (call_exec_0..17, each call_id distinct)
      //   1 js card (call_js_1, title from arguments.title)
      //   1 load_workspace_dependencies card (call_lwd_1)
      //  20 total tool-summary cards. Plus any reasoning/text cards (none here
      //  because we didn't emit agentMessage/reasoning events).
      final toolCards = runtime.messages
          .where(
            (message) =>
                (message.cardData?['type'] ?? '').toString() ==
                'agent_tool_summary',
          )
          .toList();
      expect(
        toolCards,
        hasLength(20),
        reason:
            'Every function_call (incl. exec_command/js/load_workspace_dependencies) '
            'should produce its own tool card.',
      );

      // Verify a few specific cards.
      final execCard0 = toolCards.firstWhere(
        (m) => m.id.startsWith('call_exec_0'),
      );
      expect(execCard0.cardData!['toolType'], 'terminal');
      expect(execCard0.cardData!['toolTitle'], 'pwd');
      expect(execCard0.cardData!['terminalOutput'], contains('output pwd'));

      final searchCard = toolCards.firstWhere(
        (m) => (m.cardData!['toolTitle'] ?? '').toString().startsWith('rg -n'),
      );
      expect(
        searchCard.cardData!['toolType'],
        'search',
        reason:
            'rg invocations should be classified as search via _inferToolTypeFromCommand',
      );

      final jsCard = toolCards.firstWhere(
        (m) => m.id.startsWith('call_js_1'),
      );
      expect(
        jsCard.cardData!['toolTitle'],
        'Inspect modules and dependencies',
        reason:
            'js tool should show arguments.title instead of "js" '
            '(the user-reported regression)',
      );
      expect(jsCard.cardData!['status'], 'success');

      final lwdCard = toolCards.firstWhere(
        (m) => m.id.startsWith('call_lwd_1'),
      );
      expect(
        (lwdCard.cardData!['toolTitle'] ?? '').toString(),
        contains('load_workspace_dependencies'),
      );
    },
  );

  test(
    'item/started mcpToolCall without title falls back to tool short name',
    () {
      reducer.reduce(
        runtime: runtime,
        event: {
          'message': {
            'method': 'item/started',
            'params': {
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'item': {
                'id': 'mcp-1',
                'type': 'mcpToolCall',
                'tool': 'plain_tool',
                'arguments': '{}',
              },
            },
          },
        },
      );

      final cardData = runtime.messages.single.cardData!;
      expect(cardData['toolTitle'], 'plain_tool');
    },
  );
}
