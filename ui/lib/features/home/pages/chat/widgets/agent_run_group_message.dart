import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ui/features/home/pages/chat/tool_activity_utils.dart';
import 'package:ui/features/home/pages/chat/utils/agent_run_timeline.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/agent_tool_transcript.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/card_widget_factory.dart'
    show OnBeforeTaskExecute, OnRequestAuthorize;
import 'package:ui/features/home/pages/command_overlay/widgets/message_bubble.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/services/agent_avatar_service.dart';
import 'package:ui/services/app_background_service.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/widgets/agent_avatar.dart';

class AgentRunGroupMessage extends StatefulWidget {
  const AgentRunGroupMessage({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onBeforeTaskExecute,
    this.onCancelTask,
    this.onRetryAgentMessage,
    this.parentScrollController,
    this.onParentScrollHandoff,
    this.onRequestAuthorize,
    this.onStreamingTextLayoutChanged,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
    this.appearanceConfig = AppBackgroundConfig.defaults,
  });

  final AgentRunTimelineGroup group;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final OnBeforeTaskExecute onBeforeTaskExecute;
  final void Function(String taskId)? onCancelTask;
  final ValueChanged<ChatMessageModel>? onRetryAgentMessage;
  final ScrollController? parentScrollController;
  final VoidCallback? onParentScrollHandoff;
  final OnRequestAuthorize? onRequestAuthorize;
  final VoidCallback? onStreamingTextLayoutChanged;
  final AppBackgroundVisualProfile visualProfile;
  final AppBackgroundConfig appearanceConfig;

  @override
  State<AgentRunGroupMessage> createState() => _AgentRunGroupMessageState();
}

class _AgentRunGroupMessageState extends State<AgentRunGroupMessage>
    with SingleTickerProviderStateMixin {
  static const Duration _kToggleDuration = Duration(milliseconds: 260);

  late final AnimationController _expandController;
  late final Animation<double> _sizeFactor;
  late final Animation<double> _opacity;
  late final Animation<double> _lift;
  bool _isNotifyingParentDuringAnimation = false;
  final Set<String> _expandedToolGroupKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: _kToggleDuration,
      reverseDuration: _kToggleDuration,
      value: widget.expanded ? 1.0 : 0.0,
    );
    _sizeFactor = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubicEmphasized,
    );
    _opacity = CurvedAnimation(
      parent: _expandController,
      curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: const Interval(0.0, 0.72, curve: Curves.easeOutCubic),
    );
    _lift = Tween<double>(begin: -6, end: 0).animate(
      CurvedAnimation(
        parent: _expandController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _expandController.addListener(_handleAnimationTick);
    _expandController.addStatusListener(_handleAnimationStatusChanged);
    AgentAvatarService.ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant AgentRunGroupMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.taskId != oldWidget.group.taskId) {
      _expandedToolGroupKeys.clear();
    }
    if (widget.expanded == oldWidget.expanded) {
      return;
    }
    _isNotifyingParentDuringAnimation = true;
    if (widget.expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  void dispose() {
    _expandController
      ..removeListener(_handleAnimationTick)
      ..removeStatusListener(_handleAnimationStatusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleAnimationTick() {
    if (!mounted || !_isNotifyingParentDuringAnimation) {
      return;
    }
    widget.onStreamingTextLayoutChanged?.call();
  }

  void _handleAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    final shouldNotifyParent = _isNotifyingParentDuringAnimation;
    _isNotifyingParentDuringAnimation = false;
    if (!mounted) {
      return;
    }
    setState(() {});
    if (shouldNotifyParent) {
      widget.onStreamingTextLayoutChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final processMessages = widget.group.processMessagesOldestFirst;
    final visibleMessages = widget.group.visibleMessagesOldestFirst;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AgentRunSummaryHeader(
          key: ValueKey('agent-run-summary-${widget.group.taskId}'),
          group: widget.group,
          taskId: widget.group.taskId,
          expanded: widget.expanded,
          onTap: widget.onToggleExpanded,
        ),
        _buildAnimatedProcessSection(processMessages),
        ...visibleMessages.map(
          (message) => MessageBubble(
            key: ValueKey('agent-run-${widget.group.taskId}-${message.id}'),
            message: message,
            onBeforeTaskExecute: widget.onBeforeTaskExecute,
            onCancelTask: widget.onCancelTask,
            onRetryAgentMessage: () =>
                widget.onRetryAgentMessage?.call(message),
            enableThinkingCollapse: false,
            parentScrollController: widget.parentScrollController,
            onParentScrollHandoff: widget.onParentScrollHandoff,
            onRequestAuthorize: widget.onRequestAuthorize,
            onStreamingTextLayoutChanged: widget.onStreamingTextLayoutChanged,
            visualProfile: widget.visualProfile,
            appearanceConfig: widget.appearanceConfig,
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedProcessSection(List<ChatMessageModel> processMessages) {
    if (processMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    final shouldShow =
        widget.expanded ||
        _expandController.isAnimating ||
        _expandController.value > 0.001;
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final firstThinkingMessageId = _firstThinkingMessageId(processMessages);

    return AnimatedBuilder(
      animation: _expandController,
      child: Column(
        key: ValueKey('agent-run-process-${widget.group.taskId}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildProcessWidgets(processMessages, firstThinkingMessageId),
      ),
      builder: (context, child) {
        final sizeFactor = _sizeFactor.value.clamp(0.0, 1.0);
        final opacity = _opacity.value.clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: sizeFactor,
              child: Transform.translate(
                offset: Offset(0, _lift.value),
                child: IgnorePointer(
                  ignoring: !widget.expanded && !_expandController.isAnimating,
                  child: Opacity(opacity: opacity, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildProcessWidgets(
    List<ChatMessageModel> processMessages,
    String? firstThinkingMessageId,
  ) {
    final widgets = <Widget>[];
    var index = 0;
    while (index < processMessages.length) {
      final message = processMessages[index];
      if (_isAgentToolSummaryMessage(message)) {
        final toolMessages = <ChatMessageModel>[message];
        var nextIndex = index + 1;
        while (nextIndex < processMessages.length &&
            _isAgentToolSummaryMessage(processMessages[nextIndex])) {
          toolMessages.add(processMessages[nextIndex]);
          nextIndex += 1;
        }
        if (toolMessages.length > 1) {
          final groupKey = _toolGroupKey(widget.group.taskId, toolMessages);
          final expanded = _expandedToolGroupKeys.contains(groupKey);
          widgets.add(
            _AgentToolCallGroup(
              key: ValueKey('agent-tool-call-group-$groupKey'),
              groupKey: groupKey,
              messages: toolMessages,
              expanded: expanded,
              onToggle: () => _toggleToolGroup(groupKey),
              buildMessageBubble: _buildMessageBubble,
            ),
          );
        } else {
          widgets.add(
            _buildMessageBubble(
              toolMessages.single,
              firstThinkingMessageId: firstThinkingMessageId,
            ),
          );
        }
        index = nextIndex;
        continue;
      }

      widgets.add(
        _buildMessageBubble(
          message,
          firstThinkingMessageId: firstThinkingMessageId,
        ),
      );
      index += 1;
    }
    return widgets;
  }

  MessageBubble _buildMessageBubble(
    ChatMessageModel message, {
    String? firstThinkingMessageId,
  }) {
    final hideAvatar =
        firstThinkingMessageId != null && message.id == firstThinkingMessageId;
    return MessageBubble(
      key: ValueKey('agent-run-${widget.group.taskId}-${message.id}'),
      message: message,
      onBeforeTaskExecute: widget.onBeforeTaskExecute,
      onCancelTask: widget.onCancelTask,
      onRetryAgentMessage: () => widget.onRetryAgentMessage?.call(message),
      enableThinkingCollapse: true,
      thinkingAutoCollapseOnComplete: true,
      showThinkingAvatarOverride: hideAvatar ? false : null,
      parentScrollController: widget.parentScrollController,
      onParentScrollHandoff: widget.onParentScrollHandoff,
      onRequestAuthorize: widget.onRequestAuthorize,
      onStreamingTextLayoutChanged: widget.onStreamingTextLayoutChanged,
      visualProfile: widget.visualProfile,
      appearanceConfig: widget.appearanceConfig,
    );
  }

  void _toggleToolGroup(String groupKey) {
    setState(() {
      if (!_expandedToolGroupKeys.add(groupKey)) {
        _expandedToolGroupKeys.remove(groupKey);
      }
    });
    widget.onStreamingTextLayoutChanged?.call();
  }

  String? _firstThinkingMessageId(List<ChatMessageModel> processMessages) {
    for (final message in processMessages) {
      if ((message.cardData?['type'] ?? '').toString() == 'deep_thinking') {
        return message.id;
      }
    }
    return null;
  }
}

bool _isAgentToolSummaryMessage(ChatMessageModel message) {
  return (message.cardData?['type'] ?? '').toString() ==
      kAgentToolSummaryCardType;
}

const String _kCodexAgentRunAvatarAsset = 'assets/home/chat/codex.svg';

/// A run group is treated as "codex" if any of its messages (visible or
/// collapsed) was produced by the codex reducer — those carry
/// cardData.uiStyle == 'codex_tool'. We use this to swap the avatar for the
/// codex glyph and to keep the collapsed-state header concise ("已处理"
/// instead of "已运行 N 条命令 · 已读取 M 个文件…").
bool _agentRunGroupIsCodex(AgentRunTimelineGroup group) {
  bool hasCodexStyle(ChatMessageModel message) {
    return (message.cardData?['uiStyle'] ?? '').toString().trim() ==
        'codex_tool';
  }

  for (final message in group.processMessagesNewestFirst) {
    if (hasCodexStyle(message)) return true;
  }
  for (final message in group.visibleMessagesNewestFirst) {
    if (hasCodexStyle(message)) return true;
  }
  return false;
}

String _toolGroupKey(String taskId, List<ChatMessageModel> messages) {
  return '$taskId-${messages.map((message) => message.id).join('-')}';
}

// NOTE: `_toolCountSummary` was the previous source of the
// "已运行 X 条命令 · 已读取 Y 个文件 …" header label. The user explicitly
// asked for both the collapsed AND expanded agent-run headers (and the
// inner tool-group capsule) to read the generic "已处理" instead, so this
// helper now has no callers and was deleted. The per-message-type
// counters live on individually rendered tool cards if anyone needs them
// later.

class _AgentToolCallGroup extends StatelessWidget {
  const _AgentToolCallGroup({
    super.key,
    required this.groupKey,
    required this.messages,
    required this.expanded,
    required this.onToggle,
    required this.buildMessageBubble,
  });

  final String groupKey;
  final List<ChatMessageModel> messages;
  final bool expanded;
  final VoidCallback onToggle;
  final MessageBubble Function(
    ChatMessageModel message, {
    String? firstThinkingMessageId,
  })
  buildMessageBubble;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final primaryCard = _primaryCardData(messages);
    final status = (primaryCard['status'] ?? 'running').toString();
    final toolType = (primaryCard['toolType'] ?? '').toString();
    final mutedColor = palette.textSecondary.withValues(
      alpha: context.isDarkTheme ? 0.78 : 0.68,
    );
    final titleColor = palette.textSecondary.withValues(
      alpha: context.isDarkTheme ? 0.94 : 0.88,
    );
    final overlayColor = palette.accentPrimary.withValues(
      alpha: context.isDarkTheme ? 0.10 : 0.06,
    );
    final isEnglish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'en';
    final title = _toolGroupTitle(messages, isEnglish: isEnglish);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.90,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: _toolGroupTooltip(messages),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('agent-tool-call-group-toggle-$groupKey'),
                  onTap: onToggle,
                  splashColor: overlayColor,
                  highlightColor: overlayColor,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(2, 5, 5, 5),
                    child: Row(
                      children: [
                        Icon(
                          resolveAgentToolStatusIcon(status, toolType),
                          size: 16,
                          color: mutedColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                              height: 1.18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${messages.length}',
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: messages
                            .map((message) => buildMessageBubble(message))
                            .toList(growable: false),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _primaryCardData(List<ChatMessageModel> messages) {
    for (final message in messages) {
      final cardData = message.cardData;
      if ((cardData?['status'] ?? '').toString() == 'running') {
        return cardData!;
      }
    }
    return messages.first.cardData ?? const <String, dynamic>{};
  }

  String _toolGroupTitle(
    List<ChatMessageModel> messages, {
    required bool isEnglish,
  }) {
    // The inner tool-group capsule (multiple consecutive tool cards
    // collapsed into one chevron) was previously surfacing the per-tool
    // count summary too ("已运行 1 条命令 · 已读取 1 个文件"). The user
    // explicitly asked for the expanded run UI to match the collapsed
    // header, so this capsule also shows the generic "已处理" — its own
    // count text was the only place left after fixing the outer header.
    return isEnglish ? 'Processed' : '已处理';
  }

  String _toolGroupTooltip(List<ChatMessageModel> messages) {
    return messages
        .map((message) => message.cardData)
        .whereType<Map<String, dynamic>>()
        .map(resolveAgentToolTitle)
        .where((title) => title.trim().isNotEmpty)
        .join('\n');
  }
}

class _AgentRunSummaryHeader extends StatelessWidget {
  const _AgentRunSummaryHeader({
    super.key,
    required this.group,
    required this.taskId,
    required this.expanded,
    required this.onTap,
  });

  final AgentRunTimelineGroup group;
  final String taskId;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isEnglish =
        Localizations.maybeLocaleOf(context)?.languageCode == 'en';
    final palette = context.omniPalette;
    final isCodexGroup = _agentRunGroupIsCodex(group);
    // Both collapsed AND expanded show the same "已处理 <elapsed>" label.
    // The per-tool count summary was deliberately retired — the user wants
    // the header noise-free in both states. The elapsed-time suffix is
    // computed from the message timestamps inside this group (first
    // candidate message → last candidate message). If we can't derive
    // a duration (single instant), we just show "已处理".
    final baseLabel = isEnglish ? 'Processed' : '已处理';
    final elapsedLabel = _agentRunElapsedLabel(group);
    final label = elapsedLabel.isEmpty ? baseLabel : '$baseLabel  $elapsedLabel';
    final labelColor = expanded ? palette.textSecondary : palette.textTertiary;
    final lineColor = expanded
        ? palette.textSecondary.withValues(
            alpha: context.isDarkTheme ? 0.32 : 0.28,
          )
        : palette.borderSubtle.withValues(
            alpha: context.isDarkTheme ? 0.56 : 0.8,
          );

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: palette.accentPrimary.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isCodexGroup)
                  _CodexAgentRunAvatar(
                    key: ValueKey('agent-run-codex-avatar-$taskId'),
                    color: labelColor,
                  )
                else
                  ValueListenableBuilder<AgentAvatarState>(
                    valueListenable: AgentAvatarService.avatarStateNotifier,
                    builder: (context, state, _) {
                      return AgentAvatarCircle(
                        key: ValueKey('agent-run-avatar-$taskId'),
                        state: state,
                        size: 30,
                      );
                    },
                  ),
                const SizedBox(width: 8),
                // NOTE: deliberately NOT wrapping the label in Flexible. The
                // previous implementation gave Flexible(flex:1) + Expanded
                // (flex:1) the remaining row width 50/50, which left a large
                // blank gap between the label and the divider when the label
                // was short ("已处理" — the user's reported "横线长度有问题"
                // bug). Letting the label take its intrinsic width lets the
                // Expanded(line) below truly consume ALL remaining horizontal
                // space, so the chevron is glued to the right edge in every
                // state. Long labels are clipped at 60% of the row width to
                // avoid pushing the chevron off-screen.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.6,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      color: labelColor,
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: lineColor)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: expanded ? 0 : -0.25,
                  duration: _AgentRunGroupMessageState._kToggleDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  child: Icon(
                    LucideIcons.chevronDown,
                    size: 18,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Returns a short human-readable duration string ("47s", "1m 23s",
/// "1h 5m") covering the agent run from its earliest candidate message to
/// its latest. We use the timestamps already attached to the messages — the
/// timeline group is only ever built for INACTIVE runs (active runs render
/// each card individually instead of going through `_buildTimelineGroup`),
/// so the latest timestamp is the actual run end.
String _agentRunElapsedLabel(AgentRunTimelineGroup group) {
  int? earliestMs;
  int? latestMs;
  void visit(Iterable<ChatMessageModel> messages) {
    for (final message in messages) {
      final ms = message.createAt.millisecondsSinceEpoch;
      if (ms <= 0) {
        continue;
      }
      if (earliestMs == null || ms < earliestMs!) {
        earliestMs = ms;
      }
      if (latestMs == null || ms > latestMs!) {
        latestMs = ms;
      }
    }
  }

  visit(group.processMessagesNewestFirst);
  visit(group.visibleMessagesNewestFirst);
  if (earliestMs == null || latestMs == null || latestMs! <= earliestMs!) {
    return '';
  }
  final elapsedSec = ((latestMs! - earliestMs!) / 1000).round();
  if (elapsedSec < 1) {
    return '';
  }
  if (elapsedSec < 60) {
    return '${elapsedSec}s';
  }
  final minutes = elapsedSec ~/ 60;
  final remainingSeconds = elapsedSec % 60;
  if (minutes < 60) {
    if (remainingSeconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m ${remainingSeconds}s';
  }
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) {
    return '${hours}h';
  }
  return '${hours}h ${remainingMinutes}m';
}

/// Drop-in replacement for `AgentAvatarCircle` used by codex agent runs:
/// renders the codex glyph (`assets/home/chat/codex.svg`) inside a 30px
/// circular surface so the visual rhythm matches the user-avatar variant.
class _CodexAgentRunAvatar extends StatelessWidget {
  const _CodexAgentRunAvatar({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final backgroundColor = context.isDarkTheme
        ? palette.surfaceSecondary.withValues(alpha: 0.66)
        : palette.surfaceElevated.withValues(alpha: 0.92);
    final borderColor = palette.borderSubtle.withValues(
      alpha: context.isDarkTheme ? 0.48 : 0.72,
    );
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: SvgPicture.asset(
        _kCodexAgentRunAvatarAsset,
        width: 18,
        height: 18,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }
}
