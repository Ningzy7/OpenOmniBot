import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/services/home_greeting_settings_service.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/widgets/glass_popup.dart';
import 'package:ui/widgets/omni_glass.dart';
import '../../../../../models/chat_message_model.dart';
import '../../../../../services/app_background_service.dart';
import '../../../../../widgets/app_background_widgets.dart';
import '../chat_page_models.dart';
import '../utils/agent_run_timeline.dart';
import '../../command_overlay/widgets/message_bubble.dart';
import '../../command_overlay/widgets/chat_input_area.dart';
import 'agent_run_group_message.dart';
import 'chat_empty_greeting.dart';

const String _kChatAppBarUpdateSparklesAsset =
    'assets/home/chat/update_sparkles.svg';
const String _kChatAppBarAgentIconAsset = 'assets/home/chat/agent.svg';
const String _kChatAppBarCodexIconAsset = 'assets/home/chat/codex.svg';
const String _kChatAppBarModeMenuClosedIconAsset =
    'assets/home/chat/mode_menu_closed.svg';
const String _kChatAppBarModeMenuOpenIconAsset =
    'assets/home/chat/mode_menu_open.svg';
const String _kChatAppBarPureChatIconAsset = 'assets/home/chat/pure_chat.svg';
const String _kChatAppBarWorkspaceIconAsset =
    'assets/home/workspace_folder_icon.svg';

const List<Color> _kDarkChatAccentGradient = <Color>[
  Color(0xFFAA9774),
  Color(0xFF8FA38A),
];

const double _kChatAppBarMenuButtonSize = 50;
const double _kChatAppBarAccessoryButtonSize = 40;
const double _kChatAppBarAccessoryGap = 12;
const double _kChatAppBarIslandMaxWidth = 176;
const double _kChatAppBarRightActionSlotWidth = 50;

enum ChatSurfaceMode { workspace, normal, openclaw }

const List<ChatSurfaceMode> kVisibleChatSurfaceModes = <ChatSurfaceMode>[
  ChatSurfaceMode.normal,
  ChatSurfaceMode.workspace,
];

/// 聊天页面 AppBar
class ChatAppBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback? onAgentTap;
  final VoidCallback? onPureChatToggleTap;
  final VoidCallback? onCodexTap;
  final VoidCallback? onPrimaryModeTap;
  final VoidCallback onCompanionTap;
  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onModeChanged;
  final String? activeModelId;
  final ValueChanged<BuildContext>? onModelTap;
  final ChatIslandDisplayLayer displayLayer;
  final VoidCallback? onInteracted;
  final ValueChanged<ChatIslandDisplayLayer> onDisplayLayerChanged;
  final ValueChanged<BuildContext> onTerminalEnvironmentTap;
  final VoidCallback onTerminalTap;
  final VoidCallback onBrowserTap;
  final bool hasTerminalEnvironment;
  final bool isBrowserEnabled;
  final String? activeToolType;
  final bool isCompanionModeEnabled;
  final bool isCompanionToggleLoading;
  final bool isCodexReady;
  final bool isCodexConnected;
  final bool isCodexLoading;
  final bool isCodexSelected;
  final bool isAgentSelected;
  final bool showAppUpdateIndicator;
  final VoidCallback? onAppUpdateTap;
  final String? appUpdateTooltip;
  final bool translucent;
  final AppBackgroundVisualProfile visualProfile;
  final bool showMenuButton;
  final bool showSurfaceSwitcher;
  final bool showPureChatToggle;
  final bool isPureChatSelected;
  final bool isPureChatToggleLocked;
  final bool showWorkspacePaneButton;
  final VoidCallback? onWorkspacePaneTap;

  const ChatAppBar({
    super.key,
    required this.onMenuTap,
    this.onAgentTap,
    this.onPureChatToggleTap,
    this.onCodexTap,
    this.onPrimaryModeTap,
    required this.onCompanionTap,
    required this.activeMode,
    required this.onModeChanged,
    this.activeModelId,
    this.onModelTap,
    this.displayLayer = ChatIslandDisplayLayer.mode,
    this.onInteracted,
    required this.onDisplayLayerChanged,
    required this.onTerminalEnvironmentTap,
    required this.onTerminalTap,
    required this.onBrowserTap,
    this.hasTerminalEnvironment = false,
    this.isBrowserEnabled = false,
    this.activeToolType,
    this.isCompanionModeEnabled = false,
    this.isCompanionToggleLoading = false,
    this.isCodexReady = false,
    this.isCodexConnected = false,
    this.isCodexLoading = false,
    this.isCodexSelected = false,
    this.isAgentSelected = true,
    this.showAppUpdateIndicator = false,
    this.onAppUpdateTap,
    this.appUpdateTooltip,
    this.translucent = false,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
    this.showMenuButton = true,
    this.showSurfaceSwitcher = true,
    this.showPureChatToggle = false,
    this.isPureChatSelected = false,
    this.isPureChatToggleLocked = true,
    this.showWorkspacePaneButton = false,
    this.onWorkspacePaneTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final iconTint = translucent
        ? visualProfile.appBarIconColor
        : context.isDarkTheme
        ? palette.textPrimary
        : Colors.grey[800]!;
    final primaryModeIconAsset = isCodexSelected
        ? _kChatAppBarCodexIconAsset
        : isPureChatSelected
        ? _kChatAppBarPureChatIconAsset
        : _kChatAppBarAgentIconAsset;
    const updateTint = Color(0xFFD4A017);
    final showWorkspaceButton =
        showWorkspacePaneButton && onWorkspacePaneTap != null;
    final showUpdateShortcutButton =
        showAppUpdateIndicator && onAppUpdateTap != null;
    const showModeShortcutButton = true;
    final appBarBackgroundColor = showSurfaceSwitcher
        ? palette.pageBackground
        : palette.surfacePrimary;
    return ColoredBox(
      key: const ValueKey('chat-app-bar-background'),
      color: translucent ? Colors.transparent : appBarBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SizedBox(
          height: 50,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const leftActionRowWidth = _kChatAppBarAccessoryButtonSize;
              final leftReservedSpace =
                  (showMenuButton ? _kChatAppBarMenuButtonSize : 0) +
                  leftActionRowWidth +
                  _kChatAppBarAccessoryGap * 2;
              final rightActionCount =
                  (showUpdateShortcutButton ? 1 : 0) +
                  (showWorkspaceButton ? 1 : 0) +
                  (showModeShortcutButton ? 1 : 0);
              final rightReservedSpace =
                  rightActionCount * _kChatAppBarRightActionSlotWidth +
                  _kChatAppBarAccessoryGap;
              final symmetricReservedSpace = math.max(
                leftReservedSpace,
                rightReservedSpace,
              );
              final islandWidth = math
                  .min(
                    _kChatAppBarIslandMaxWidth,
                    math.max(
                      0,
                      constraints.maxWidth - symmetricReservedSpace * 2,
                    ),
                  )
                  .toDouble();
              final islandCenterX = constraints.maxWidth / 2;
              final islandLeft = islandCenterX - islandWidth / 2;
              final accessoryLeftEdge = showMenuButton
                  ? _kChatAppBarMenuButtonSize + _kChatAppBarAccessoryGap
                  : _kChatAppBarAccessoryGap;
              final accessoryRightEdge = islandLeft - _kChatAppBarAccessoryGap;
              final accessoryAvailableWidth = math
                  .max(0, accessoryRightEdge - accessoryLeftEdge)
                  .toDouble();
              final accessoryMaxLeft = math.max(
                accessoryLeftEdge,
                accessoryRightEdge - leftActionRowWidth,
              );
              final accessoryRowLeft =
                  (accessoryLeftEdge +
                          ((accessoryAvailableWidth - leftActionRowWidth) / 2)
                              .clamp(0, double.infinity))
                      .clamp(accessoryLeftEdge, accessoryMaxLeft)
                      .toDouble();

              return Stack(
                alignment: Alignment.center,
                children: [
                  if (showMenuButton)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: _kChatAppBarMenuButtonSize,
                      child: Center(
                        child: GestureDetector(
                          key: const ValueKey('chat-app-bar-menu-button'),
                          onTap: onMenuTap,
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.all(15),
                            child: SvgPicture.asset(
                              'assets/home/drawer_icon.svg',
                              width: 20,
                              height: 20,
                              colorFilter: ColorFilter.mode(
                                iconTint,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: accessoryRowLeft,
                    top: 0,
                    bottom: 0,
                    width: leftActionRowWidth.toDouble(),
                    child: Row(
                      children: [
                        _ChatAppBarCompanionButton(
                          isEnabled: isCompanionModeEnabled,
                          isLoading: isCompanionToggleLoading,
                          iconTint: iconTint,
                          selectedColor: context.isDarkTheme
                              ? palette.accentPrimary
                              : const Color(0xFF1930D9),
                          onTap: onCompanionTap,
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      key: const ValueKey('chat-app-bar-island'),
                      width: islandWidth,
                      child: _ChatModeModelSwitcher(
                        activeMode: activeMode,
                        onModeChanged: onModeChanged,
                        activeModelId: activeModelId,
                        onModelTap: onModelTap,
                        displayLayer: displayLayer,
                        onInteracted: onInteracted,
                        onDisplayLayerChanged: onDisplayLayerChanged,
                        onTerminalEnvironmentTap: onTerminalEnvironmentTap,
                        onTerminalTap: onTerminalTap,
                        onBrowserTap: onBrowserTap,
                        hasTerminalEnvironment: hasTerminalEnvironment,
                        isBrowserEnabled: isBrowserEnabled,
                        activeToolType: activeToolType,
                        translucent: translucent,
                        visualProfile: visualProfile,
                        showSurfaceLayer: showSurfaceSwitcher,
                        primaryModeIconAsset: primaryModeIconAsset,
                        onPrimaryModeTap: onPrimaryModeTap,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showUpdateShortcutButton)
                          GestureDetector(
                            key: const ValueKey('chat-app-update-button'),
                            onTap: onAppUpdateTap,
                            child: Tooltip(
                              message:
                                  appUpdateTooltip ??
                                  (LegacyTextLocalizer.isEnglish
                                      ? 'Check for updates'
                                      : '检查更新'),
                              child: Container(
                                color: Colors.transparent,
                                padding: const EdgeInsets.all(15),
                                child: SvgPicture.asset(
                                  _kChatAppBarUpdateSparklesAsset,
                                  width: 18,
                                  height: 18,
                                  colorFilter: const ColorFilter.mode(
                                    updateTint,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (showWorkspaceButton)
                          SizedBox(
                            width: _kChatAppBarRightActionSlotWidth,
                            height: _kChatAppBarRightActionSlotWidth,
                            child: Center(
                              child: _ChatAppBarWorkspaceButton(
                                iconTint: iconTint,
                                onTap: onWorkspacePaneTap!,
                              ),
                            ),
                          ),
                        if (showModeShortcutButton)
                          SizedBox(
                            width: _kChatAppBarRightActionSlotWidth,
                            height: _kChatAppBarRightActionSlotWidth,
                            child: Center(
                              child: _ChatAppBarModeShortcutButton(
                                key: const ValueKey(
                                  'chat-app-bar-pure-chat-button',
                                ),
                                iconTint: iconTint,
                                isCodexLoading: isCodexLoading,
                                isCodexSelected: isCodexSelected,
                                isAgentSelected: isAgentSelected,
                                isPureChatSelected: isPureChatSelected,
                                isPureChatToggleLocked: isPureChatToggleLocked,
                                onAgentTap: onAgentTap,
                                onCodexTap: onCodexTap,
                                onPureChatToggleTap: onPureChatToggleTap,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ChatAppBarModeShortcutAction { agent, codex, pureChat }

class _ChatAppBarCompanionButton extends StatelessWidget {
  const _ChatAppBarCompanionButton({
    required this.isEnabled,
    required this.isLoading,
    required this.iconTint,
    required this.selectedColor,
    required this.onTap,
  });

  final bool isEnabled;
  final bool isLoading;
  final Color iconTint;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isEnabled ? selectedColor : iconTint;
    return GestureDetector(
      key: const ValueKey('chat-app-companion-button'),
      onTap: isLoading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kChatAppBarAccessoryButtonSize,
        height: _kChatAppBarAccessoryButtonSize,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              : SvgPicture.asset(
                  'assets/home/avatar.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
        ),
      ),
    );
  }
}

class _ChatAppBarWorkspaceButton extends StatelessWidget {
  const _ChatAppBarWorkspaceButton({
    required this.iconTint,
    required this.onTap,
  });

  final Color iconTint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: LegacyTextLocalizer.isEnglish ? 'Show workspace' : '显示工作区',
      child: GestureDetector(
        key: const ValueKey('chat-app-bar-workspace-pane-button'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _kChatAppBarAccessoryButtonSize,
          height: _kChatAppBarAccessoryButtonSize,
          child: Center(
            child: SvgPicture.asset(
              _kChatAppBarWorkspaceIconAsset,
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatAppBarModeShortcutButton extends StatefulWidget {
  const _ChatAppBarModeShortcutButton({
    super.key,
    required this.iconTint,
    required this.isCodexLoading,
    required this.isCodexSelected,
    required this.isAgentSelected,
    required this.isPureChatSelected,
    required this.isPureChatToggleLocked,
    required this.onAgentTap,
    required this.onCodexTap,
    required this.onPureChatToggleTap,
  });

  final Color iconTint;
  final bool isCodexLoading;
  final bool isCodexSelected;
  final bool isAgentSelected;
  final bool isPureChatSelected;
  final bool isPureChatToggleLocked;
  final VoidCallback? onAgentTap;
  final VoidCallback? onCodexTap;
  final VoidCallback? onPureChatToggleTap;

  @override
  State<_ChatAppBarModeShortcutButton> createState() =>
      _ChatAppBarModeShortcutButtonState();
}

class _ChatAppBarModeShortcutButtonState
    extends State<_ChatAppBarModeShortcutButton> {
  bool _isOpen = false;

  Future<void> _openMenu() async {
    if (_isOpen) {
      return;
    }
    final anchor = glassPopupAnchorFromContext(context);
    if (anchor == null) {
      return;
    }
    setState(() => _isOpen = true);
    final palette = context.omniPalette;
    final selectedColor = palette.accentPrimary;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final canSelectPureChat =
        widget.isCodexSelected ||
        (!widget.isPureChatToggleLocked && widget.onPureChatToggleTap != null);

    final action = await showGlassPopup<_ChatAppBarModeShortcutAction>(
      context: context,
      anchor: anchor,
      // 与上方触发按钮零间距相连——触发按钮玻璃的下边线 == popup 玻璃的上边线,
      // 拼成一个完整胶囊。
      verticalGap: 0,
      child: _ChatAppBarModeShortcutMenuContent(
        // 宽度与触发按钮 (_kChatAppBarAccessoryButtonSize = 40) 完全一致,
        // edgeAlign 策略下 popup 的左右边 = 按钮的左右边,垂直对齐到一条线。
        width: _kChatAppBarAccessoryButtonSize,
        items: [
          _ChatAppBarModeShortcutMenuItemData(
            action: _ChatAppBarModeShortcutAction.agent,
            iconAsset: _kChatAppBarAgentIconAsset,
            tooltip: isEnglish ? 'Agent mode' : 'Agent 模式',
            selected: widget.isAgentSelected,
            enabled: widget.onAgentTap != null,
            iconSize: 20,
          ),
          _ChatAppBarModeShortcutMenuItemData(
            action: _ChatAppBarModeShortcutAction.codex,
            iconAsset: _kChatAppBarCodexIconAsset,
            tooltip: isEnglish ? 'Codex mode' : 'Codex 模式',
            selected: widget.isCodexSelected,
            enabled: !widget.isCodexLoading && widget.onCodexTap != null,
            iconSize: 20,
          ),
          _ChatAppBarModeShortcutMenuItemData(
            action: _ChatAppBarModeShortcutAction.pureChat,
            iconAsset: _kChatAppBarPureChatIconAsset,
            tooltip: isEnglish ? 'Pure chat' : '纯聊天模式',
            selected: widget.isPureChatSelected,
            enabled: canSelectPureChat,
            iconSize: 18,
          ),
        ],
        selectedColor: selectedColor,
        iconTint: widget.iconTint,
        disabledTint: widget.iconTint.withValues(alpha: 0.42),
      ),
    );
    if (mounted) {
      setState(() => _isOpen = false);
    }
    switch (action) {
      case _ChatAppBarModeShortcutAction.agent:
        widget.onAgentTap?.call();
        break;
      case _ChatAppBarModeShortcutAction.codex:
        widget.onCodexTap?.call();
        break;
      case _ChatAppBarModeShortcutAction.pureChat:
        widget.onPureChatToggleTap?.call();
        break;
      case null:
        break;
    }
  }

  String _closedIconAsset() {
    if (widget.isCodexSelected) {
      return _kChatAppBarCodexIconAsset;
    }
    if (widget.isPureChatSelected) {
      return _kChatAppBarPureChatIconAsset;
    }
    if (widget.isAgentSelected) {
      return _kChatAppBarAgentIconAsset;
    }
    return _kChatAppBarModeMenuClosedIconAsset;
  }

  Widget _buildClosedIcon(Color color) {
    if (widget.isCodexLoading && !widget.isCodexSelected) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    final iconSize = widget.isCodexSelected ? 22.0 : 20.0;
    return SvgPicture.asset(
      _closedIconAsset(),
      width: iconSize,
      height: iconSize,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _buildOpenIcon(Color color) {
    return SvgPicture.asset(
      _kChatAppBarModeMenuOpenIconAsset,
      width: 20,
      height: 20,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final selectedColor = palette.accentPrimary;
    final hasSelectedMode =
        widget.isAgentSelected ||
        widget.isCodexSelected ||
        widget.isPureChatSelected;
    final effectiveIconColor = _isOpen || hasSelectedMode
        ? selectedColor
        : widget.iconTint;
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final icon = Center(
      child: _isOpen
          ? _buildOpenIcon(effectiveIconColor)
          : _buildClosedIcon(effectiveIconColor),
    );
    return Tooltip(
      message: _isOpen
          ? (isEnglish ? 'Close mode menu' : '收起模式菜单')
          : (isEnglish ? 'Switch chat mode' : '切换聊天模式'),
      child: GestureDetector(
        onTap: _openMenu,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _kChatAppBarAccessoryButtonSize,
          height: _kChatAppBarAccessoryButtonSize,
          // 玻璃 pill 只在 mode 列表展开时显示——平时是干净的图标按钮。
          // 展开时:上半圆 (radius 20 = 半宽) + 下边直,跟下方 popup 的"上直
          // 下半圆"无缝拼成一个完整的胶囊形状。
          child: _isOpen
              ? _GlassPillIcon(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  omitBottomBorder: true,
                  child: icon,
                )
              : icon,
        ),
      ),
    );
  }
}

/// 给 app bar accessory button 用的小型玻璃 pill 背景 (轻量版 [OmniGlassPanel])。
/// 适合 40×40 小尺寸按钮,只保留必要的模糊和淡 tint,不带大阴影。
///
/// 可传入自定义 [borderRadius] —— 跟下方展开 popup 拼接时用半圆即可
/// (`BorderRadius.vertical(top: Radius.circular(halfWidth))`)。
/// 拼接时还应设 [omitBottomBorder] = true,这样下边那条 1px 线不会和 popup 顶边
/// 的边线/高光在接缝处叠加成可见的"分割线"。
class _GlassPillIcon extends StatelessWidget {
  const _GlassPillIcon({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.omitBottomBorder = false,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool omitBottomBorder;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    // 渐变 tint 与 [OmniGlassPanel] 完全对齐(同 alpha)——胶囊模式下
    // 上半 (trigger) 与下半 (popup) 接缝处不能有任何饱和度差,否则会出现
    // "上面比下面亮一点"的视觉断层。改之前 _GlassPillIcon 用的是更深的
    // 0.32/0.18 (dark) / 0.55/0.30 (light),独立存在时手感更"实",但拼成
    // 胶囊就露馅了。这里统一回 0.26/0.12 (dark) / 0.40/0.18 (light)。
    final topTint = isDark
        ? palette.surfacePrimary.withValues(alpha: 0.26)
        : Colors.white.withValues(alpha: 0.40);
    final bottomTint = isDark
        ? palette.surfaceSecondary.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.18);
    // 深色模式下边线压到 0.06——之前 0.18 在暗底上绕图标一圈,视觉上就是
    // 白色描边的"框",而不是玻璃。和 [OmniGlassPanel] 同步,把"边界"交给
    // 顶部高光 + 渐变 tint + popup 阴影去做,均匀边线退到肉眼几乎察觉不到。
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.72);
    final borderSide = BorderSide(color: borderColor);
    final BoxBorder border = omitBottomBorder
        ? Border(top: borderSide, left: borderSide, right: borderSide)
        : Border.all(color: borderColor);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: border,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [topTint, bottomTint],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ChatAppBarModeShortcutMenuItemData {
  const _ChatAppBarModeShortcutMenuItemData({
    required this.action,
    required this.iconAsset,
    required this.tooltip,
    required this.selected,
    required this.enabled,
    this.iconSize = 20,
  });

  final _ChatAppBarModeShortcutAction action;
  final String iconAsset;
  final String tooltip;
  final bool selected;
  final bool enabled;
  final double iconSize;
}

class _ChatAppBarModeShortcutMenuContent extends StatelessWidget {
  const _ChatAppBarModeShortcutMenuContent({
    required this.width,
    required this.items,
    required this.selectedColor,
    required this.iconTint,
    required this.disabledTint,
  });

  final double width;
  final List<_ChatAppBarModeShortcutMenuItemData> items;
  final Color selectedColor;
  final Color iconTint;
  final Color disabledTint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: OmniGlassPanel(
        // 上边直 + 下半圆 (radius 20 = 半宽),跟上方触发按钮的"上半圆 + 下边直"
        // 在中线 zero-gap 处无缝拼接,整体看上去是一个完整的胶囊。
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(20),
        ),
        // 接缝处:省略顶边 1px 边线 + 关闭顶部高光条,
        // 否则与上方触发按钮的下边线会叠成可见的横线。
        omitTopBorder: true,
        showTopHighlight: false,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                _ChatAppBarModeShortcutMenuRow(
                  item: item,
                  selectedColor: selectedColor,
                  iconTint: iconTint,
                  disabledTint: disabledTint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatAppBarModeShortcutMenuRow extends StatelessWidget {
  const _ChatAppBarModeShortcutMenuRow({
    required this.item,
    required this.selectedColor,
    required this.iconTint,
    required this.disabledTint,
  });

  final _ChatAppBarModeShortcutMenuItemData item;
  final Color selectedColor;
  final Color iconTint;
  final Color disabledTint;

  @override
  Widget build(BuildContext context) {
    final color = !item.enabled
        ? disabledTint
        : (item.selected ? selectedColor : iconTint);
    return Tooltip(
      message: item.tooltip,
      child: InkWell(
        onTap: item.enabled
            ? () => Navigator.of(context).pop(item.action)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 40,
          child: Center(
            child: SvgPicture.asset(
              item.iconAsset,
              width: item.iconSize,
              height: item.iconSize,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatModeModelSwitcher extends StatefulWidget {
  const _ChatModeModelSwitcher({
    required this.activeMode,
    required this.onModeChanged,
    this.activeModelId,
    this.onModelTap,
    required this.displayLayer,
    this.onInteracted,
    required this.onDisplayLayerChanged,
    required this.onTerminalEnvironmentTap,
    required this.onTerminalTap,
    required this.onBrowserTap,
    required this.hasTerminalEnvironment,
    required this.isBrowserEnabled,
    this.activeToolType,
    this.translucent = false,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
    this.showSurfaceLayer = true,
    required this.primaryModeIconAsset,
    this.onPrimaryModeTap,
  });

  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onModeChanged;
  final String? activeModelId;
  final ValueChanged<BuildContext>? onModelTap;
  final ChatIslandDisplayLayer displayLayer;
  final VoidCallback? onInteracted;
  final ValueChanged<ChatIslandDisplayLayer> onDisplayLayerChanged;
  final ValueChanged<BuildContext> onTerminalEnvironmentTap;
  final VoidCallback onTerminalTap;
  final VoidCallback onBrowserTap;
  final bool hasTerminalEnvironment;
  final bool isBrowserEnabled;
  final String? activeToolType;
  final bool translucent;
  final AppBackgroundVisualProfile visualProfile;
  final bool showSurfaceLayer;
  final String primaryModeIconAsset;
  final VoidCallback? onPrimaryModeTap;

  @override
  State<_ChatModeModelSwitcher> createState() => _ChatModeModelSwitcherState();
}

class _ChatModeModelSwitcherState extends State<_ChatModeModelSwitcher> {
  static const String _terminalIconAsset = 'assets/home/chat/terminal.svg';
  static const String _browserIconAsset = 'assets/home/chat/browser.svg';
  static const String _environmentIconAsset =
      'assets/home/chat/environment.svg';
  static const Duration _switchDuration = Duration(milliseconds: 460);
  static const double _verticalSwitchThreshold = 10;
  static const double _verticalVelocityThreshold = 240;
  static const double _switcherHeight = 32;
  static const double _offstageLayerGap = 2;

  double _verticalDragDelta = 0;
  double _horizontalDragDelta = 0;

  int get _activeVisibleModeIndex {
    final index = kVisibleChatSurfaceModes.indexOf(widget.activeMode);
    if (index >= 0) {
      return index;
    }
    return 0;
  }

  String get _modelLabel {
    final text = (widget.activeModelId ?? '').trim();
    if (text.isEmpty) {
      return LegacyTextLocalizer.isEnglish ? 'No model set' : '未设置模型';
    }
    return text;
  }

  bool get _canRevealModelLabel =>
      widget.activeMode == ChatSurfaceMode.normal &&
      (widget.activeModelId ?? '').trim().isNotEmpty;

  List<ChatIslandDisplayLayer> get _visibleLayers => widget.showSurfaceLayer
      ? const <ChatIslandDisplayLayer>[
          ChatIslandDisplayLayer.tools,
          ChatIslandDisplayLayer.model,
          ChatIslandDisplayLayer.mode,
        ]
      : const <ChatIslandDisplayLayer>[
          ChatIslandDisplayLayer.tools,
          ChatIslandDisplayLayer.model,
        ];

  ChatIslandDisplayLayer get _effectiveDisplayLayer =>
      _visibleLayers.contains(widget.displayLayer)
      ? widget.displayLayer
      : ChatIslandDisplayLayer.model;

  int _layerOrder(ChatIslandDisplayLayer layer) =>
      _visibleLayers.indexOf(layer);

  void _handleSliderInteraction() {
    widget.onInteracted?.call();
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!widget.showSurfaceLayer ||
        widget.activeMode != ChatSurfaceMode.normal ||
        widget.displayLayer != ChatIslandDisplayLayer.model) {
      return;
    }
    _horizontalDragDelta += details.delta.dx;
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!widget.showSurfaceLayer ||
        widget.activeMode != ChatSurfaceMode.normal ||
        widget.displayLayer != ChatIslandDisplayLayer.model) {
      _horizontalDragDelta = 0;
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final shouldSwitch =
        _horizontalDragDelta.abs() > 14 || velocity.abs() > 250;
    if (!shouldSwitch) {
      _horizontalDragDelta = 0;
      return;
    }
    final intent = _horizontalDragDelta + velocity * 0.015;
    _horizontalDragDelta = 0;
    final currentIndex = _activeVisibleModeIndex;
    final delta = intent > 0 ? 1 : -1;
    final targetIndex = (currentIndex + delta).clamp(
      0,
      kVisibleChatSurfaceModes.length - 1,
    );
    widget.onInteracted?.call();
    widget.onModeChanged(kVisibleChatSurfaceModes[targetIndex]);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragDelta += details.delta.dy;
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldToggle =
        _verticalDragDelta.abs() > _verticalSwitchThreshold ||
        velocity.abs() > _verticalVelocityThreshold;
    if (!shouldToggle) {
      _verticalDragDelta = 0;
      return;
    }
    final intent = _verticalDragDelta + velocity * 0.015;
    _verticalDragDelta = 0;

    if (widget.activeMode != ChatSurfaceMode.normal) {
      return;
    }
    widget.onInteracted?.call();
    if (intent > 0) {
      if (_effectiveDisplayLayer != ChatIslandDisplayLayer.tools) {
        widget.onDisplayLayerChanged(ChatIslandDisplayLayer.tools);
      }
      return;
    }
    if ((_canRevealModelLabel || !widget.showSurfaceLayer) &&
        _effectiveDisplayLayer != ChatIslandDisplayLayer.model) {
      widget.onDisplayLayerChanged(ChatIslandDisplayLayer.model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final restingLabelColor = widget.translucent
        ? widget.visualProfile.subtleTextColor
        : context.isDarkTheme
        ? palette.textSecondary
        : const Color(0xFF9DA9BB);
    final islandBaseColor = widget.translucent
        ? palette.surfacePrimary
        : context.isDarkTheme
        ? palette.surfaceSecondary
        : palette.surfacePrimary;
    final modelLabelWidget = Builder(
      builder: (anchorContext) {
        final text = Text(
          _modelLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: restingLabelColor,
            fontWeight: FontWeight.w500,
          ),
        );
        if (widget.onModelTap == null) {
          return Center(child: text);
        }
        return InkWell(
          onTap: () {
            widget.onInteracted?.call();
            widget.onModelTap?.call(anchorContext);
          },
          borderRadius: BorderRadius.circular(999),
          child: Center(child: text),
        );
      },
    );
    final toolLayerWidget = _ChatToolSlider(
      environmentIconAsset: _environmentIconAsset,
      terminalIconAsset: _terminalIconAsset,
      browserIconAsset: _browserIconAsset,
      activeToolType: widget.activeToolType,
      hasTerminalEnvironment: widget.hasTerminalEnvironment,
      onTerminalEnvironmentTap: (anchorContext) {
        widget.onInteracted?.call();
        widget.onTerminalEnvironmentTap(anchorContext);
      },
      isBrowserEnabled: widget.isBrowserEnabled,
      onTerminalTap: () {
        widget.onInteracted?.call();
        widget.onTerminalTap();
      },
      onBrowserTap: () {
        widget.onInteracted?.call();
        widget.onBrowserTap();
      },
      onInteracted: _handleSliderInteraction,
      visualProfile: widget.visualProfile,
    );
    final currentOrder = _layerOrder(_effectiveDisplayLayer);

    double topFor(ChatIslandDisplayLayer layer) {
      final delta = _layerOrder(layer) - currentOrder;
      if (delta == 0) return 0;
      final direction = delta > 0 ? 1 : -1;
      return delta * _switcherHeight + direction * _offstageLayerGap;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundSurfaceColor(
          translucent: widget.translucent,
          baseColor: islandBaseColor,
          opacity: 0.78,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: widget.translucent
              ? widget.visualProfile.islandBorderColor
              : palette.borderSubtle.withValues(alpha: 0.72),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: _switcherHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            onHorizontalDragEnd: _handleHorizontalDragEnd,
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
            onVerticalDragCancel: () {
              _verticalDragDelta = 0;
            },
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.mode),
                  child: widget.showSurfaceLayer
                      ? ClipRect(
                          child: ChatModeSlider(
                            activeMode: widget.activeMode,
                            onChanged: widget.onModeChanged,
                            onInteracted: _handleSliderInteraction,
                            visualProfile: widget.visualProfile,
                            primaryIconAsset: widget.primaryModeIconAsset,
                            onPrimaryModeTap: widget.onPrimaryModeTap,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.model),
                  child: modelLabelWidget,
                ),
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.tools),
                  child: ClipRect(child: toolLayerWidget),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatToolSlider extends StatelessWidget {
  final String environmentIconAsset;
  final String terminalIconAsset;
  final String browserIconAsset;
  final String? activeToolType;
  final bool hasTerminalEnvironment;
  final ValueChanged<BuildContext> onTerminalEnvironmentTap;
  final bool isBrowserEnabled;
  final VoidCallback onTerminalTap;
  final VoidCallback onBrowserTap;
  final VoidCallback? onInteracted;
  final AppBackgroundVisualProfile visualProfile;

  const _ChatToolSlider({
    required this.environmentIconAsset,
    required this.terminalIconAsset,
    required this.browserIconAsset,
    this.activeToolType,
    required this.hasTerminalEnvironment,
    required this.onTerminalEnvironmentTap,
    this.isBrowserEnabled = false,
    required this.onTerminalTap,
    required this.onBrowserTap,
    this.onInteracted,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
  });

  bool get _isBrowserActive => activeToolType?.trim() == 'browser';
  bool get _isTerminalActive => !_isBrowserActive;

  Alignment get _activeAlignment =>
      _isBrowserActive ? Alignment.centerRight : Alignment.center;

  @override
  Widget build(BuildContext context) {
    final activeGradient = context.isDarkTheme
        ? _kDarkChatAccentGradient
        : const <Color>[Color(0xFF2DA5F0), Color(0xFF1930D9)];
    return SizedBox(
      height: 32,
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: _activeAlignment,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: activeGradient,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: _buildEnvironmentButton(context)),
                Expanded(
                  child: _buildToolSegment(
                    context: context,
                    key: const ValueKey('chat-island-terminal-button'),
                    isSelected: _isTerminalActive,
                    isEnabled: true,
                    tooltip: LegacyTextLocalizer.isEnglish
                        ? 'Open terminal'
                        : '打开终端',
                    onTap: onTerminalTap,
                    child: SvgPicture.asset(
                      terminalIconAsset,
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildToolSegment(
                    context: context,
                    key: const ValueKey('chat-island-browser-button'),
                    isSelected: _isBrowserActive,
                    isEnabled: isBrowserEnabled,
                    tooltip: isBrowserEnabled
                        ? (LegacyTextLocalizer.isEnglish
                              ? 'Open browser for current session'
                              : '打开当前会话浏览器')
                        : (LegacyTextLocalizer.isEnglish
                              ? 'No browser session available'
                              : '当前会话还没有可用的浏览器会话'),
                    onTap: onBrowserTap,
                    child: SvgPicture.asset(
                      browserIconAsset,
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentButton(BuildContext context) {
    final inactiveColor = context.isDarkTheme
        ? context.omniPalette.textSecondary
        : visualProfile.secondaryTextColor;
    return Builder(
      builder: (anchorContext) {
        return Tooltip(
          message: LegacyTextLocalizer.isEnglish
              ? 'Manage terminal environment variables'
              : '管理终端环境变量',
          child: InkWell(
            key: const ValueKey('chat-island-terminal-env-button'),
            onTap: () {
              onInteracted?.call();
              onTerminalEnvironmentTap(anchorContext);
            },
            borderRadius: BorderRadius.circular(999),
            child: SizedBox.expand(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(inactiveColor, BlendMode.srcIn),
                  child: SvgPicture.asset(
                    environmentIconAsset,
                    width: 15,
                    height: 15,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolSegment({
    required BuildContext context,
    required Key key,
    required bool isSelected,
    required bool isEnabled,
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final inactiveColor = context.isDarkTheme
        ? context.omniPalette.textSecondary
        : visualProfile.secondaryTextColor;
    final color = !isEnabled
        ? inactiveColor.withValues(alpha: 0.72)
        : isSelected
        ? Theme.of(context).colorScheme.onPrimary
        : inactiveColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: key,
        onTap: isEnabled
            ? () {
                onInteracted?.call();
                onTap();
              }
            : null,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            scale: isSelected ? 1 : 0.95,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class ChatModeSlider extends StatefulWidget {
  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onChanged;
  final VoidCallback? onInteracted;
  final AppBackgroundVisualProfile visualProfile;
  final String primaryIconAsset;
  final VoidCallback? onPrimaryModeTap;

  const ChatModeSlider({
    super.key,
    required this.activeMode,
    required this.onChanged,
    this.onInteracted,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
    this.primaryIconAsset = _kChatAppBarAgentIconAsset,
    this.onPrimaryModeTap,
  });

  @override
  State<ChatModeSlider> createState() => _ChatModeSliderState();
}

class _ChatModeSliderState extends State<ChatModeSlider> {
  static const String _workspaceIconAsset = 'assets/home/chat/workspace.svg';

  double _dragDelta = 0;

  int get _activeVisibleModeIndex {
    final index = kVisibleChatSurfaceModes.indexOf(widget.activeMode);
    if (index >= 0) {
      return index;
    }
    return 0;
  }

  void _handleDragEnd({double velocity = 0}) {
    final intent = _dragDelta + velocity * 0.015;
    final shouldSwitch = _dragDelta.abs() > 14 || velocity.abs() > 250;
    if (shouldSwitch) {
      final currentIndex = _activeVisibleModeIndex;
      final delta = intent > 0 ? 1 : -1;
      final targetIndex = (currentIndex + delta).clamp(
        0,
        kVisibleChatSurfaceModes.length - 1,
      );
      widget.onChanged(kVisibleChatSurfaceModes[targetIndex]);
    }
    _dragDelta = 0;
  }

  @override
  Widget build(BuildContext context) {
    final activeGradient = context.isDarkTheme
        ? _kDarkChatAccentGradient
        : const <Color>[Color(0xFF2DA5F0), Color(0xFF1930D9)];
    final alignment = _activeVisibleModeIndex == 0
        ? Alignment.centerLeft
        : Alignment.centerRight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        _dragDelta += details.delta.dx;
        widget.onInteracted?.call();
      },
      onHorizontalDragEnd: (details) {
        widget.onInteracted?.call();
        _handleDragEnd(velocity: details.primaryVelocity ?? 0);
      },
      onTapUp: (details) {
        widget.onInteracted?.call();
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(details.globalPosition);
        final segmentWidth = box.size.width / kVisibleChatSurfaceModes.length;
        final targetIndex = (local.dx / segmentWidth).floor().clamp(
          0,
          kVisibleChatSurfaceModes.length - 1,
        );
        if (targetIndex == 0 &&
            targetIndex == _activeVisibleModeIndex &&
            widget.onPrimaryModeTap != null) {
          widget.onPrimaryModeTap?.call();
          return;
        }
        widget.onChanged(kVisibleChatSurfaceModes[targetIndex]);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: 1 / kVisibleChatSurfaceModes.length,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: activeGradient,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildModeIcon(
                    isSelected: widget.activeMode == ChatSurfaceMode.normal,
                    child: SvgPicture.asset(
                      widget.primaryIconAsset,
                      key: const ValueKey('chat-mode-slider-primary-icon'),
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildModeIcon(
                    isSelected: widget.activeMode == ChatSurfaceMode.workspace,
                    child: SvgPicture.asset(
                      _workspaceIconAsset,
                      key: const ValueKey('chat-mode-slider-workspace-icon'),
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeIcon({required bool isSelected, required Widget child}) {
    final inactiveColor = context.isDarkTheme
        ? context.omniPalette.textSecondary
        : widget.visualProfile.secondaryTextColor;
    final color = isSelected
        ? Theme.of(context).colorScheme.onPrimary
        : inactiveColor;
    return Center(
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        scale: isSelected ? 1 : 0.95,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: child,
        ),
      ),
    );
  }
}

/// 消息列表
class ChatMessageList extends StatefulWidget {
  final List<ChatMessageModel> messages;
  final ScrollController scrollController;
  final Future<void> Function() onBeforeTaskExecute;
  final void Function(String taskId)? onCancelTask;
  final ValueChanged<ChatMessageModel>? onRetryAgentMessage;
  final void Function(List<String> requiredPermissionIds)? onRequestAuthorize;
  final double bottomOverlayInset;
  final void Function(ChatMessageModel message, LongPressStartDetails details)?
  onUserMessageLongPressStart;
  final String? editingUserMessageId;
  final TextEditingController? userMessageEditController;
  final VoidCallback? onUserMessageEditCancelled;
  final ValueChanged<ChatMessageModel>? onUserMessageEditSaved;
  final Future<void> Function()? onLoadMore;
  final bool hasMore;
  final Set<String> activeAgentTaskIds;
  final Set<String>? expandedAgentRunTaskIds;
  final ValueChanged<Set<String>>? onExpandedAgentRunTaskIdsChanged;
  final AppBackgroundVisualProfile visualProfile;
  final AppBackgroundConfig appearanceConfig;
  final bool showEmptyGreeting;
  final bool liftEmptyGreeting;
  final List<HomeQuickPrompt> emptyGreetingQuickPrompts;
  final List<String> emptyGreetingPinnedQuickPromptIds;
  final ValueChanged<HomeQuickPrompt>? onQuickPromptSelected;
  final String? emptyGreetingCodexWorkspaceName;
  final VoidCallback? onEmptyGreetingCodexWorkspaceTap;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.onBeforeTaskExecute,
    this.onCancelTask,
    this.onRetryAgentMessage,
    this.onRequestAuthorize,
    this.bottomOverlayInset = 0,
    this.onUserMessageLongPressStart,
    this.editingUserMessageId,
    this.userMessageEditController,
    this.onUserMessageEditCancelled,
    this.onUserMessageEditSaved,
    this.onLoadMore,
    this.hasMore = false,
    this.activeAgentTaskIds = const <String>{},
    this.expandedAgentRunTaskIds,
    this.onExpandedAgentRunTaskIdsChanged,
    this.visualProfile = AppBackgroundVisualProfile.defaultProfile,
    this.appearanceConfig = AppBackgroundConfig.defaults,
    this.showEmptyGreeting = true,
    this.liftEmptyGreeting = false,
    this.emptyGreetingQuickPrompts = const <HomeQuickPrompt>[],
    this.emptyGreetingPinnedQuickPromptIds = const <String>[],
    this.onQuickPromptSelected,
    this.emptyGreetingCodexWorkspaceName,
    this.onEmptyGreetingCodexWorkspaceTap,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const Duration _kAgentRunToggleAutoStickSuppression = Duration(
    milliseconds: 420,
  );
  static const Duration _kEditingUserMessageRevealDuration = Duration(
    milliseconds: 220,
  );
  bool _stickToBottomScheduled = false;
  bool _autoStickToLatest = true;
  bool _outerScrollWasUserDriven = false;
  bool _isAutoLoadingHistory = false;
  final Set<String> _localExpandedAgentRunTaskIds = <String>{};
  static const double _latestEdgeTolerance = 48.0;
  static const double _manualLatestAttachTolerance = 2.0;
  static const double _historyLoadTriggerExtent = 180.0;
  ObservableChatMessageList? _observableMessages;
  DateTime? _autoStickSuppressedUntil;
  GlobalKey? _editingUserMessageRevealKey;
  String? _editingUserMessageRevealKeyId;

  Set<String> get _expandedAgentRunTaskIds =>
      widget.expandedAgentRunTaskIds ?? _localExpandedAgentRunTaskIds;

  bool get _isAutoStickTemporarilySuppressed {
    final suppressedUntil = _autoStickSuppressedUntil;
    if (suppressedUntil == null) {
      return false;
    }
    if (DateTime.now().isBefore(suppressedUntil)) {
      return true;
    }
    _autoStickSuppressedUntil = null;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _bindObservableMessages(widget.messages);
    _scheduleStickToBottom();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindObservableMessages(widget.messages);
    final scrollControllerChanged =
        oldWidget.scrollController != widget.scrollController;
    if (scrollControllerChanged) {
      _autoStickToLatest = true;
      _outerScrollWasUserDriven = false;
      _autoStickSuppressedUntil = null;
    }
    final editingMessageChanged =
        oldWidget.editingUserMessageId != widget.editingUserMessageId;
    final bottomInsetChanged =
        (oldWidget.bottomOverlayInset - widget.bottomOverlayInset).abs() >= 0.5;
    if (widget.editingUserMessageId == null) {
      _editingUserMessageRevealKey = null;
      _editingUserMessageRevealKeyId = null;
    } else if (editingMessageChanged ||
        bottomInsetChanged ||
        scrollControllerChanged) {
      _autoStickSuppressedUntil = DateTime.now().add(
        _kEditingUserMessageRevealDuration,
      );
      _outerScrollWasUserDriven = false;
      _scheduleEditingUserMessageReveal(widget.editingUserMessageId!);
      return;
    }
    if (_autoStickToLatest) {
      _autoStickToLatest = true;
      _scheduleStickToLatest();
      return;
    }
    if (_isAutoStickTemporarilySuppressed) {
      return;
    }
    if (_isNearLatest(null, _manualLatestAttachTolerance)) {
      _autoStickToLatest = true;
      _scheduleStickToLatest();
    }
  }

  @override
  void dispose() {
    _observableMessages?.removeListener(_handleObservableMessagesChanged);
    super.dispose();
  }

  List<ScrollPosition> _attachedPositions() {
    if (!widget.scrollController.hasClients) {
      return const <ScrollPosition>[];
    }
    return widget.scrollController.positions.toList(growable: false);
  }

  bool _isNearLatest([
    ScrollMetrics? metrics,
    double tolerance = _latestEdgeTolerance,
  ]) {
    final resolvedMetrics = metrics;
    if (resolvedMetrics != null) {
      return _distanceToLatest(resolvedMetrics) <= tolerance;
    }
    final positions = _attachedPositions();
    if (positions.isEmpty) {
      return true;
    }
    return positions.every(
      (position) => _distanceToLatest(position) <= tolerance,
    );
  }

  double _latestOffset(ScrollMetrics metrics) {
    return switch (metrics.axisDirection) {
      AxisDirection.down || AxisDirection.right => metrics.maxScrollExtent,
      AxisDirection.up || AxisDirection.left => metrics.minScrollExtent,
    };
  }

  double _distanceToLatest(ScrollMetrics metrics) {
    return (metrics.pixels - _latestOffset(metrics)).abs();
  }

  void _scheduleStickToBottom() => _scheduleStickToLatest();

  void _scheduleStickToLatest() {
    if (!_autoStickToLatest || _isAutoStickTemporarilySuppressed) {
      return;
    }
    if (_stickToBottomScheduled) {
      return;
    }
    _stickToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickToBottomScheduled = false;
      if (!mounted) {
        if (mounted) {
          _scheduleStickToBottom();
        }
        return;
      }
      final positions = _attachedPositions();
      if (positions.isEmpty) {
        if (mounted) {
          _scheduleStickToBottom();
        }
        return;
      }
      if (!_autoStickToLatest) {
        return;
      }
      for (final position in positions) {
        final target = _latestOffset(position);
        if ((target - position.pixels).abs() < 0.5) {
          continue;
        }
        position.jumpTo(target);
      }
    });
  }

  void _handleStreamingTextLayoutChanged() {
    if (_autoStickToLatest && !_isAutoStickTemporarilySuppressed) {
      _scheduleStickToLatest();
    }
  }

  void _bindObservableMessages(List<ChatMessageModel> messages) {
    final nextObservable = messages is ObservableChatMessageList
        ? messages
        : null;
    if (identical(_observableMessages, nextObservable)) {
      return;
    }
    _observableMessages?.removeListener(_handleObservableMessagesChanged);
    _observableMessages = nextObservable;
    _observableMessages?.addListener(_handleObservableMessagesChanged);
  }

  void _handleObservableMessagesChanged() {
    if (!mounted) {
      return;
    }
    _collapseCancelledAgentRuns();
    if (_autoStickToLatest && !_isAutoStickTemporarilySuppressed) {
      _scheduleStickToLatest();
    }
    setState(() {});
  }

  void _collapseCancelledAgentRuns() {
    final collapsedTaskIds = _cancelledAgentRunTaskIds(
      _expandedAgentRunTaskIds,
    );
    if (collapsedTaskIds.isEmpty) {
      return;
    }
    final nextExpandedTaskIds = Set<String>.from(_expandedAgentRunTaskIds)
      ..removeAll(collapsedTaskIds);
    if (widget.expandedAgentRunTaskIds != null) {
      widget.onExpandedAgentRunTaskIdsChanged?.call(nextExpandedTaskIds);
      return;
    }
    _localExpandedAgentRunTaskIds
      ..clear()
      ..addAll(nextExpandedTaskIds);
    widget.onExpandedAgentRunTaskIdsChanged?.call(nextExpandedTaskIds);
  }

  Set<String> _cancelledAgentRunTaskIds(Set<String> expandedTaskIds) {
    if (expandedTaskIds.isEmpty) {
      return const <String>{};
    }
    final normalizedExpandedTaskIds = expandedTaskIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedExpandedTaskIds.isEmpty) {
      return const <String>{};
    }
    final collapsedTaskIds = <String>{};
    final messages = _observableMessages ?? widget.messages;
    for (final message in messages) {
      final taskId = agentRunParentTaskId(message);
      if (taskId == null || !normalizedExpandedTaskIds.contains(taskId)) {
        continue;
      }
      if (_isCancelledAgentRunMessage(message)) {
        collapsedTaskIds.add(taskId);
      }
    }
    return collapsedTaskIds;
  }

  bool _isCancelledAgentRunMessage(ChatMessageModel message) {
    if (message.type != 1 || message.user != 2) {
      return false;
    }
    final text = (message.text ?? '').trim().toLowerCase();
    return text == '任务已取消' ||
        text == 'task canceled' ||
        text == 'task cancelled';
  }

  void _handleParentScrollHandoff() {
    _autoStickToLatest = false;
    _outerScrollWasUserDriven = false;
  }

  void _suspendAutoStickForAgentRunToggle() {
    _autoStickToLatest = false;
    _outerScrollWasUserDriven = false;
    _autoStickSuppressedUntil = DateTime.now().add(
      _kAgentRunToggleAutoStickSuppression,
    );
  }

  void _toggleAgentRunGroup(String taskId) {
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return;
    }
    _suspendAutoStickForAgentRunToggle();
    final nextExpandedTaskIds = Set<String>.from(_expandedAgentRunTaskIds);
    if (nextExpandedTaskIds.contains(normalizedTaskId)) {
      nextExpandedTaskIds.remove(normalizedTaskId);
    } else {
      nextExpandedTaskIds.add(normalizedTaskId);
    }
    if (widget.expandedAgentRunTaskIds != null) {
      widget.onExpandedAgentRunTaskIdsChanged?.call(nextExpandedTaskIds);
    } else {
      setState(() {
        _localExpandedAgentRunTaskIds
          ..clear()
          ..addAll(nextExpandedTaskIds);
      });
      widget.onExpandedAgentRunTaskIdsChanged?.call(nextExpandedTaskIds);
    }
  }

  double _distanceToOldest(ScrollMetrics metrics) {
    return (metrics.pixels - metrics.minScrollExtent).abs();
  }

  ScrollPosition? _closestAttachedPosition({
    required double pixels,
    required double minScrollExtent,
    required double maxScrollExtent,
  }) {
    final positions = _attachedPositions();
    if (positions.isEmpty) {
      return null;
    }
    ScrollPosition? bestMatch;
    var bestScore = double.infinity;
    for (final position in positions) {
      final score =
          (position.pixels - pixels).abs() +
          (position.minScrollExtent - minScrollExtent).abs() +
          (position.maxScrollExtent - maxScrollExtent).abs();
      if (score < bestScore) {
        bestScore = score;
        bestMatch = position;
      }
    }
    return bestMatch;
  }

  void _maybeLoadOlderMessages(ScrollMetrics metrics) {
    if (_isAutoLoadingHistory || !widget.hasMore || widget.onLoadMore == null) {
      return;
    }
    if (_distanceToOldest(metrics) > _historyLoadTriggerExtent) {
      return;
    }
    _isAutoLoadingHistory = true;
    unawaited(
      _loadOlderMessagesAndPreserveViewport(
        anchorPixels: metrics.pixels,
        anchorMinScrollExtent: metrics.minScrollExtent,
        anchorMaxScrollExtent: metrics.maxScrollExtent,
      ),
    );
  }

  Future<void> _loadOlderMessagesAndPreserveViewport({
    required double anchorPixels,
    required double anchorMinScrollExtent,
    required double anchorMaxScrollExtent,
  }) async {
    try {
      await widget.onLoadMore!.call();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _isAutoLoadingHistory = false;
          return;
        }
        final position = _closestAttachedPosition(
          pixels: anchorPixels,
          minScrollExtent: anchorMinScrollExtent,
          maxScrollExtent: anchorMaxScrollExtent,
        );
        if (position == null) {
          _isAutoLoadingHistory = false;
          return;
        }
        final extentDelta = position.maxScrollExtent - anchorMaxScrollExtent;
        if (extentDelta.abs() >= 0.5) {
          final targetOffset = (anchorPixels + extentDelta).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
          if ((position.pixels - targetOffset).abs() >= 0.5) {
            position.jumpTo(targetOffset);
          }
        }
        _isAutoLoadingHistory = false;
      });
    } catch (_) {
      _isAutoLoadingHistory = false;
      rethrow;
    }
  }

  bool _handleListScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final shouldCheckAutoLoad =
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification ||
        notification is ScrollEndNotification;
    if (shouldCheckAutoLoad) {
      _maybeLoadOlderMessages(notification.metrics);
    }

    final isUserDrivenUpdate =
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null);
    if (isUserDrivenUpdate) {
      _outerScrollWasUserDriven = true;
      if (_distanceToLatest(notification.metrics) >
          _manualLatestAttachTolerance) {
        _autoStickToLatest = false;
      }
      return false;
    }
    if (notification is ScrollEndNotification) {
      if (_outerScrollWasUserDriven &&
          _isNearLatest(notification.metrics, _manualLatestAttachTolerance)) {
        _autoStickToLatest = true;
      }
      _outerScrollWasUserDriven = false;
    }
    return false;
  }

  GlobalKey? _editingRevealKeyForMessage(String? messageId) {
    if (messageId == null || messageId != widget.editingUserMessageId) {
      return null;
    }
    if (_editingUserMessageRevealKey == null ||
        _editingUserMessageRevealKeyId != messageId) {
      _editingUserMessageRevealKey = GlobalKey();
      _editingUserMessageRevealKeyId = messageId;
    }
    return _editingUserMessageRevealKey;
  }

  void _scheduleEditingUserMessageReveal(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.editingUserMessageId != messageId) {
        return;
      }
      final targetContext = _editingUserMessageRevealKey?.currentContext;
      if (targetContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        targetContext,
        duration: _kEditingUserMessageRevealDuration,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  ValueListenable<ChatMessageModel>? _messageListenableFor(
    ObservableChatMessageList messages,
    String messageId,
  ) {
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index == -1) {
      return null;
    }
    return messages.listenableAt(index);
  }

  List<Listenable> _groupMessageListenablesFor(
    ObservableChatMessageList messages,
    AgentRunTimelineGroup group,
  ) {
    final seenIds = <String>{};
    final listenables = <Listenable>[];
    for (final message in [
      ...group.visibleMessagesNewestFirst,
      ...group.processMessagesNewestFirst,
    ]) {
      if (!seenIds.add(message.id)) {
        continue;
      }
      final listenable = _messageListenableFor(messages, message.id);
      if (listenable != null) {
        listenables.add(listenable);
      }
    }
    return listenables;
  }

  AgentRunTimelineGroup _refreshTimelineGroup(
    ObservableChatMessageList messages,
    AgentRunTimelineGroup group,
  ) {
    final latestById = <String, ChatMessageModel>{
      for (final message in messages) message.id: message,
    };
    List<ChatMessageModel> refresh(List<ChatMessageModel> source) {
      return source
          .map((message) => latestById[message.id] ?? message)
          .toList(growable: false);
    }

    return AgentRunTimelineGroup(
      taskId: group.taskId,
      visibleMessagesNewestFirst: refresh(group.visibleMessagesNewestFirst),
      processMessagesNewestFirst: refresh(group.processMessagesNewestFirst),
    );
  }

  Widget _buildTimelineListRow({
    required List<ChatMessageModel> messageSource,
    required AgentRunTimelineEntry entry,
    required String? latestUserMessageId,
    required EdgeInsets padding,
  }) {
    final rowKey = ValueKey('chat-message-list-item-${entry.key}');

    Widget buildRow(AgentRunTimelineEntry rowEntry, {Key? key}) {
      return _ChatTimelineListRow(
        key: key,
        entry: rowEntry,
        latestUserMessageId: latestUserMessageId,
        editingUserMessageId: widget.editingUserMessageId,
        userMessageEditController: widget.userMessageEditController,
        onUserMessageEditCancelled: widget.onUserMessageEditCancelled,
        onUserMessageEditSaved: widget.onUserMessageEditSaved,
        padding: padding,
        onBeforeTaskExecute: widget.onBeforeTaskExecute,
        onCancelTask: widget.onCancelTask,
        onRetryAgentMessage: widget.onRetryAgentMessage,
        parentScrollController: widget.scrollController,
        onParentScrollHandoff: _handleParentScrollHandoff,
        editingUserMessageRevealKey: _editingRevealKeyForMessage(
          entry.message?.id,
        ),
        onRequestAuthorize: widget.onRequestAuthorize,
        onUserMessageLongPressStart: widget.onUserMessageLongPressStart,
        onStreamingTextLayoutChanged: _handleStreamingTextLayoutChanged,
        onToggleAgentRunGroup: _toggleAgentRunGroup,
        expandedAgentRunTaskIds: _expandedAgentRunTaskIds,
        visualProfile: widget.visualProfile,
        appearanceConfig: widget.appearanceConfig,
      );
    }

    final observableMessages = messageSource is ObservableChatMessageList
        ? messageSource
        : null;
    if (observableMessages == null) {
      return buildRow(entry, key: rowKey);
    }

    final message = entry.message;
    if (message != null) {
      final listenable = _messageListenableFor(observableMessages, message.id);
      if (listenable == null) {
        return buildRow(entry, key: rowKey);
      }
      return ValueListenableBuilder<ChatMessageModel>(
        key: rowKey,
        valueListenable: listenable,
        builder: (context, latestMessage, _) {
          return buildRow(AgentRunTimelineEntry.message(latestMessage));
        },
      );
    }

    final group = entry.group;
    if (group == null) {
      return buildRow(entry, key: rowKey);
    }
    final listenables = _groupMessageListenablesFor(observableMessages, group);
    if (listenables.isEmpty) {
      return buildRow(entry, key: rowKey);
    }
    return AnimatedBuilder(
      key: rowKey,
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        return buildRow(
          AgentRunTimelineEntry.group(
            _refreshTimelineGroup(observableMessages, group),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reservedBottomInset = widget.bottomOverlayInset
        .clamp(0.0, double.infinity)
        .toDouble();
    final pageBackgroundColor =
        !widget.appearanceConfig.isActive && context.isDarkTheme
        ? context.omniPalette.pageBackground
        : null;

    final Widget content;
    if (widget.messages.isEmpty) {
      final usePaletteText =
          !widget.appearanceConfig.isActive &&
          widget.appearanceConfig.chatTextColorMode !=
              AppBackgroundTextColorMode.custom;
      content = widget.showEmptyGreeting
          ? GestureDetector(
              onVerticalDragUpdate: (_) {},
              behavior: HitTestBehavior.opaque,
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                alignment: widget.liftEmptyGreeting
                    ? const Alignment(-1, -1)
                    : const Alignment(0, -0.18),
                child: ChatEmptyGreeting(
                  primaryTextColor: usePaletteText
                      ? context.omniPalette.textPrimary
                      : widget.visualProfile.primaryTextColor,
                  secondaryTextColor: usePaletteText
                      ? context.omniPalette.textSecondary
                      : widget.visualProfile.secondaryTextColor,
                  accentColor: context.omniPalette.accentPrimary,
                  quickPrompts: widget.emptyGreetingQuickPrompts,
                  pinnedQuickPromptIds:
                      widget.emptyGreetingPinnedQuickPromptIds,
                  onQuickPromptSelected: widget.onQuickPromptSelected,
                  codexWorkspaceName: widget.emptyGreetingCodexWorkspaceName,
                  onCodexWorkspaceTap: widget.onEmptyGreetingCodexWorkspaceTap,
                ),
              ),
            )
          : const SizedBox.expand();
      if (pageBackgroundColor == null) {
        return content;
      }
      return ColoredBox(color: pageBackgroundColor, child: content);
    }

    String? latestUserMessageId;
    final messageSource = _observableMessages ?? widget.messages;
    final timelineEntries = buildAgentRunTimelineEntries(
      List<ChatMessageModel>.from(messageSource),
      activeTaskIds: widget.activeAgentTaskIds,
    );
    for (final item in messageSource) {
      if (item.user == 1) {
        latestUserMessageId = item.id;
        break;
      }
    }
    Widget listView = ListView.builder(
      controller: widget.scrollController,
      reverse: false,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      itemCount: timelineEntries.length,
      itemBuilder: (context, index) {
        final dataIndex = timelineEntries.length - 1 - index;
        final entry = timelineEntries[dataIndex];
        final isOldestEntry = dataIndex == timelineEntries.length - 1;
        final needTopPadding = isOldestEntry && !entry.isUserMessage;
        return _buildTimelineListRow(
          messageSource: messageSource,
          entry: entry,
          latestUserMessageId: latestUserMessageId,
          padding: EdgeInsets.only(top: needTopPadding ? 24.0 : 0.0),
        );
      },
    );
    content = ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleListScrollNotification,
          child: listView,
        ),
      ),
    );

    final paddedContent = AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: reservedBottomInset),
      child: content,
    );

    if (pageBackgroundColor == null) {
      return paddedContent;
    }
    return ColoredBox(color: pageBackgroundColor, child: paddedContent);
  }
}

class _ChatTimelineListRow extends StatelessWidget {
  const _ChatTimelineListRow({
    super.key,
    required this.entry,
    required this.padding,
    required this.onBeforeTaskExecute,
    this.latestUserMessageId,
    this.editingUserMessageId,
    this.userMessageEditController,
    this.onUserMessageEditCancelled,
    this.onUserMessageEditSaved,
    this.onCancelTask,
    this.onRetryAgentMessage,
    this.parentScrollController,
    this.onParentScrollHandoff,
    this.editingUserMessageRevealKey,
    this.onRequestAuthorize,
    this.onUserMessageLongPressStart,
    this.onStreamingTextLayoutChanged,
    required this.onToggleAgentRunGroup,
    required this.expandedAgentRunTaskIds,
    required this.visualProfile,
    required this.appearanceConfig,
  });

  final AgentRunTimelineEntry entry;
  final EdgeInsets padding;
  final Future<void> Function() onBeforeTaskExecute;
  final String? latestUserMessageId;
  final String? editingUserMessageId;
  final TextEditingController? userMessageEditController;
  final VoidCallback? onUserMessageEditCancelled;
  final ValueChanged<ChatMessageModel>? onUserMessageEditSaved;
  final void Function(String taskId)? onCancelTask;
  final ValueChanged<ChatMessageModel>? onRetryAgentMessage;
  final ScrollController? parentScrollController;
  final VoidCallback? onParentScrollHandoff;
  final GlobalKey? editingUserMessageRevealKey;
  final void Function(List<String> requiredPermissionIds)? onRequestAuthorize;
  final void Function(ChatMessageModel message, LongPressStartDetails details)?
  onUserMessageLongPressStart;
  final VoidCallback? onStreamingTextLayoutChanged;
  final void Function(String taskId) onToggleAgentRunGroup;
  final Set<String> expandedAgentRunTaskIds;
  final AppBackgroundVisualProfile visualProfile;
  final AppBackgroundConfig appearanceConfig;

  @override
  Widget build(BuildContext context) {
    if (entry.message != null) {
      return _buildBubble(entry.message!);
    }
    final group = entry.group!;
    return Padding(
      padding: padding,
      child: AgentRunGroupMessage(
        group: group,
        expanded: expandedAgentRunTaskIds.contains(group.taskId),
        onToggleExpanded: () => onToggleAgentRunGroup(group.taskId),
        onBeforeTaskExecute: onBeforeTaskExecute,
        onCancelTask: onCancelTask,
        onRetryAgentMessage: onRetryAgentMessage,
        parentScrollController: parentScrollController,
        onParentScrollHandoff: onParentScrollHandoff,
        onRequestAuthorize: onRequestAuthorize,
        onStreamingTextLayoutChanged: onStreamingTextLayoutChanged,
        visualProfile: visualProfile,
        appearanceConfig: appearanceConfig,
      ),
    );
  }

  Widget _buildBubble(ChatMessageModel currentMessage) {
    final canEditUserMessage =
        currentMessage.user == 1 && currentMessage.id == latestUserMessageId;
    final isEditingUserMessage =
        canEditUserMessage &&
        editingUserMessageId == currentMessage.id &&
        userMessageEditController != null;
    final bubble = MessageBubble(
      message: currentMessage,
      key: ValueKey(
        currentMessage.dbId ?? currentMessage.contentId ?? currentMessage.id,
      ),
      onBeforeTaskExecute: onBeforeTaskExecute,
      onCancelTask: onCancelTask,
      onRetryAgentMessage: () => onRetryAgentMessage?.call(currentMessage),
      enableThinkingCollapse: true,
      parentScrollController: parentScrollController,
      onParentScrollHandoff: onParentScrollHandoff,
      onRequestAuthorize: onRequestAuthorize,
      onUserMessageLongPressStart: onUserMessageLongPressStart,
      isUserMessageEditing: isEditingUserMessage,
      userMessageEditController: isEditingUserMessage
          ? userMessageEditController
          : null,
      onCancelUserEdit: isEditingUserMessage
          ? onUserMessageEditCancelled
          : null,
      onSaveUserEdit: isEditingUserMessage
          ? () => onUserMessageEditSaved?.call(currentMessage)
          : null,
      onStreamingTextLayoutChanged: onStreamingTextLayoutChanged,
      visualProfile: visualProfile,
      appearanceConfig: appearanceConfig,
    );
    return Padding(
      padding: padding,
      child: isEditingUserMessage && editingUserMessageRevealKey != null
          ? KeyedSubtree(key: editingUserMessageRevealKey, child: bubble)
          : bubble,
    );
  }
}

/// VLM 用户输入提示
class VlmInfoPrompt extends StatelessWidget {
  final String question;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  const VlmInfoPrompt({
    super.key,
    required this.question,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F83FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Localizations.localeOf(context).languageCode == 'en'
                ? 'Need your confirmation'
                : '需要你的确认',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D3E7B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            question,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1D3E7B)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: Localizations.localeOf(context).languageCode == 'en'
                  ? 'Optional: add details. Default sends: Completed action, continue execution'
                  : '可选：补充你的操作说明，默认发送"已完成操作，继续执行"',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onDismiss,
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'en'
                        ? 'Later'
                        : '稍后再说',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  child: Text(
                    isSubmitting
                        ? (Localizations.localeOf(context).languageCode == 'en'
                              ? 'Sending...'
                              : '发送中...')
                        : (Localizations.localeOf(context).languageCode == 'en'
                              ? 'Continue'
                              : '继续执行'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 聊天输入区域包装器
class ChatInputWrapper extends StatelessWidget {
  final GlobalKey<ChatInputAreaState> inputAreaKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isProcessing;
  final Future<void> Function({String? text}) onSendMessage;
  final VoidCallback onCancelTask;
  final void Function(bool) onPopupVisibilityChanged;
  final FutureOr<void> Function()? onTerminalTap;
  final bool? openClawEnabled;
  final ValueChanged<bool>? onToggleOpenClaw;
  final VoidCallback? onLongPressOpenClaw;
  final bool useLargeComposerStyle;
  final bool useAttachmentPickerForPlus;
  final Future<void> Function()? onPickAttachment;
  final List<ChatInputAttachment> attachments;
  final ValueChanged<String>? onRemoveAttachment;
  final VoidCallback? onTriggerSlashCommand;
  final Widget? topBanner;
  final String? selectedModelOverrideId;
  final VoidCallback? onClearSelectedModelOverride;
  final double? contextUsageRatio;
  final String? contextUsageTooltipMessage;
  final VoidCallback? onLongPressContextUsageRing;
  final ValueChanged<double>? onInputHeightChanged;
  final CodexRunSettings? codexRunSettings;
  final CodexRunSettingsChanged? onCodexRunSettingsChanged;
  final FutureOr<void> Function()? onCodexRunSettingsOpened;
  final CodexPermissionMode? codexPermissionMode;
  final ValueChanged<CodexPermissionMode>? onCodexPermissionModeChanged;
  final bool useIndependentSendButton;
  final bool translucent;

  const ChatInputWrapper({
    super.key,
    required this.inputAreaKey,
    required this.controller,
    required this.focusNode,
    required this.isProcessing,
    required this.onSendMessage,
    required this.onCancelTask,
    required this.onPopupVisibilityChanged,
    this.onTerminalTap,
    this.openClawEnabled,
    this.onToggleOpenClaw,
    this.onLongPressOpenClaw,
    this.useLargeComposerStyle = false,
    this.useAttachmentPickerForPlus = false,
    this.onPickAttachment,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.onTriggerSlashCommand,
    this.topBanner,
    this.selectedModelOverrideId,
    this.onClearSelectedModelOverride,
    this.contextUsageRatio,
    this.contextUsageTooltipMessage,
    this.onLongPressContextUsageRing,
    this.onInputHeightChanged,
    this.codexRunSettings,
    this.onCodexRunSettingsChanged,
    this.onCodexRunSettingsOpened,
    this.codexPermissionMode,
    this.onCodexPermissionModeChanged,
    this.useIndependentSendButton = true,
    this.translucent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topBanner != null) ...[topBanner!, const SizedBox(height: 8)],
          ChatInputArea(
            key: inputAreaKey,
            controller: controller,
            focusNode: focusNode,
            isProcessing: isProcessing,
            onSendMessage: onSendMessage,
            onCancelTask: onCancelTask,
            onPopupVisibilityChanged: onPopupVisibilityChanged,
            onTerminalTap: onTerminalTap,
            openClawEnabled: openClawEnabled,
            onToggleOpenClaw: onToggleOpenClaw,
            onLongPressOpenClaw: onLongPressOpenClaw,
            useFrostedGlass: translucent,
            useLargeComposerStyle: useLargeComposerStyle,
            useAttachmentPickerForPlus: useAttachmentPickerForPlus,
            onPickAttachment: onPickAttachment,
            attachments: attachments,
            onRemoveAttachment: onRemoveAttachment,
            onTriggerSlashCommand: onTriggerSlashCommand,
            selectedModelOverrideId: selectedModelOverrideId,
            onClearSelectedModelOverride: onClearSelectedModelOverride,
            contextUsageRatio: contextUsageRatio,
            contextUsageTooltipMessage: contextUsageTooltipMessage,
            onLongPressContextUsageRing: onLongPressContextUsageRing,
            codexRunSettings: codexRunSettings,
            onCodexRunSettingsChanged: onCodexRunSettingsChanged,
            onCodexRunSettingsOpened: onCodexRunSettingsOpened,
            codexPermissionMode: codexPermissionMode,
            onCodexPermissionModeChanged: onCodexPermissionModeChanged,
            onInputHeightChanged: onInputHeightChanged,
            useIndependentSendButton: useIndependentSendButton,
          ),
        ],
      ),
    );
  }
}
