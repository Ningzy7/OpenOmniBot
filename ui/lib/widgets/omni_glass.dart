import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ui/theme/omni_theme_palette.dart';
import 'package:ui/theme/theme_context.dart';

class OmniGlassPanel extends StatelessWidget {
  const OmniGlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.forceDark = false,
    this.omitTopBorder = false,
    this.showTopHighlight = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final bool forceDark;

  /// 是否省略**顶边**的 1px 边线（默认 false 即画完整四边）。
  /// 当 popup 紧贴在另一块玻璃下方（如下拉模式列表贴在触发按钮下边）需要拼成
  /// 一个完整胶囊时设为 true,避免顶边那条 1px 线在拼接处形成"双线"。
  final bool omitTopBorder;

  /// 是否绘制顶部 1px 的高光渐变（默认 true）。拼接到上方玻璃时也应关掉,
  /// 否则在接缝处会出现一截多余的亮线。
  final bool showTopHighlight;

  @override
  Widget build(BuildContext context) {
    final palette = forceDark ? OmniThemePalette.dark : context.omniPalette;
    final isDark = forceDark || context.isDarkTheme;
    final topTint = isDark
        ? palette.surfacePrimary.withValues(alpha: 0.26)
        : Colors.white.withValues(alpha: 0.40);
    final bottomTint = isDark
        ? palette.surfaceSecondary.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.18);
    // 深色模式下故意把整圈边线压得极弱(0.08)——之前 0.22 在暗底上一圈白线
    // 看起来就是"PPT 描边",完全没有玻璃感。真玻璃在暗环境里是"边线几乎消
    // 失、顶部高光独自承担定义边界",所以这里把均匀边线退到肉眼几乎觉察不到,
    // 让 [highlightColor] 的顶部 1px 渐变去做"光打在玻璃顶上"的活儿。
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.82);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.86);
    final accentGlow = palette.accentPrimary.withValues(
      alpha: isDark ? 0.10 : 0.08,
    );

    final borderSide = BorderSide(color: borderColor);
    final BoxBorder border = omitTopBorder
        ? Border(
            left: borderSide,
            right: borderSide,
            bottom: borderSide,
          )
        : Border.all(color: borderColor);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
            blurRadius: isDark ? 42 : 30,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: accentGlow,
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
            child: Stack(
              children: [
                if (showTopHighlight)
                  // 顶部高光横向覆盖更广(8 vs 之前 18),让"光面"延伸出去,
                  // 不再只是中段一小截亮线——配合深色模式下基本消失的边框,
                  // 视觉上更接近真实玻璃顶边的反光。
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 0,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            highlightColor,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
