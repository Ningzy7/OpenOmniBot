import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ui/services/codex_diff_parser.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/widgets/chat_drawer_gesture_guard.dart';

class CodexDiffViewer extends StatelessWidget {
  const CodexDiffViewer({
    super.key,
    required this.summary,
    required this.padding,
    this.scrollable = true,
    this.showOverview = true,
    this.showFileHeaders = true,
  });

  final CodexDiffSummary summary;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final bool showOverview;
  final bool showFileHeaders;

  @override
  Widget build(BuildContext context) {
    final colors = _DiffViewerColors.resolve(context);
    if (summary.files.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          '暂无 diff',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final maxLineCount = summary.files.fold<int>(
      0,
      (maxLines, file) => math.max(maxLines, file.lines.length),
    );
    final lineNumberWidth = math
        .max(36.0, math.max(1, maxLineCount.toString().length) * 7.5 + 6)
        .toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 320.0;
        final minWidth = math.max(320.0, availableWidth).toDouble();
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showOverview) ...[
              _DiffOverviewBar(summary: summary, colors: colors),
              const SizedBox(height: 14),
            ],
            for (var index = 0; index < summary.files.length; index += 1) ...[
              _DiffFileSection(
                file: summary.files[index],
                minWidth: minWidth,
                lineNumberWidth: lineNumberWidth,
                colors: colors,
                showHeader: showFileHeaders,
              ),
              if (index < summary.files.length - 1) const SizedBox(height: 14),
            ],
            SizedBox(
              height: math
                  .max(12.0, theme.visualDensity.baseSizeAdjustment.dy + 12.0)
                  .toDouble(),
            ),
          ],
        );
        if (!scrollable) {
          return Padding(padding: padding, child: content);
        }
        return SingleChildScrollView(padding: padding, child: content);
      },
    );
  }
}

class _DiffOverviewBar extends StatelessWidget {
  const _DiffOverviewBar({required this.summary, required this.colors});

  final CodexDiffSummary summary;
  final _DiffViewerColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = summary.primaryPath;
    final title = summary.files.length == 1
        ? (path.isEmpty ? 'Diff' : path)
        : '${summary.files.length} 个文件';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.headerSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.gitCompareArrows, size: 18, color: colors.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildOverviewText(summary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _DiffStatPill(
            additions: summary.additions,
            deletions: summary.deletions,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

String _buildOverviewText(CodexDiffSummary summary) {
  final fileLabel = summary.files.length == 1
      ? '1 个文件'
      : '${summary.files.length} 个文件';
  return '$fileLabel · ${formatCodexDiffStat(additions: summary.additions, deletions: summary.deletions)}';
}

class _DiffFileSection extends StatelessWidget {
  const _DiffFileSection({
    required this.file,
    required this.minWidth,
    required this.lineNumberWidth,
    required this.colors,
    required this.showHeader,
  });

  final CodexDiffFile file;
  final double minWidth;
  final double lineNumberWidth;
  final _DiffViewerColors colors;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateLabel = file.isNewFile
        ? '新'
        : file.isDeletedFile
        ? '删'
        : '改';

    return _HorizontalDragShield(
      child: Container(
        decoration: BoxDecoration(
          color: colors.fileSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              ColoredBox(
                color: colors.headerSurface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                  child: Row(
                    children: [
                      Icon(
                        file.isNewFile
                            ? LucideIcons.circlePlus
                            : file.isDeletedFile
                            ? LucideIcons.circleMinus
                            : LucideIcons.fileText,
                        size: 17,
                        color: colors.icon,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.displayPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StateChip(label: stateLabel, colors: colors),
                      const SizedBox(width: 8),
                      _DiffStatPill(
                        additions: file.additions,
                        deletions: file.deletions,
                        colors: colors,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.divider),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in file.lines)
                        _DiffLineRow(
                          line: line,
                          lineNumberWidth: lineNumberWidth,
                          colors: colors,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({
    required this.line,
    required this.lineNumberWidth,
    required this.colors,
  });

  final CodexDiffLine line;
  final double lineNumberWidth;
  final _DiffViewerColors colors;

  @override
  Widget build(BuildContext context) {
    final (background, textColor, gutterColor) = switch (line.kind) {
      CodexDiffLineKind.add => (
        colors.addBackground,
        colors.lineText,
        colors.addAccent,
      ),
      CodexDiffLineKind.remove => (
        colors.removeBackground,
        colors.lineText,
        colors.removeAccent,
      ),
      CodexDiffLineKind.header => (
        colors.hunkBackground,
        colors.hunkText,
        colors.gutterText,
      ),
      CodexDiffLineKind.meta => (
        colors.metaBackground,
        colors.textSecondary,
        colors.gutterText,
      ),
      CodexDiffLineKind.context => (
        colors.contextBackground,
        colors.contextText,
        colors.gutterText,
      ),
    };

    final oldNumber = _lineNumberText(line.oldLineNumber);
    final newNumber = _lineNumberText(line.newLineNumber);
    final contentText =
        line.kind == CodexDiffLineKind.header ||
            line.kind == CodexDiffLineKind.meta
        ? line.content
        : '${line.prefix}${line.content}';

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              oldNumber,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: gutterColor,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              newNumber,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: gutterColor,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SelectableText(
            contentText,
            maxLines: 1,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  String _lineNumberText(int? value) => value == null ? ' ' : value.toString();
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.colors});

  final String label;
  final _DiffViewerColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.chipBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.chipText,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DiffStatPill extends StatelessWidget {
  const _DiffStatPill({
    required this.additions,
    required this.deletions,
    required this.colors,
  });

  final int additions;
  final int deletions;
  final _DiffViewerColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.chipBorder),
      ),
      child: Text(
        formatCodexDiffStat(additions: additions, deletions: deletions),
        style: TextStyle(
          color: additions >= deletions
              ? colors.addAccent
              : colors.removeAccent,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _HorizontalDragShield extends StatelessWidget {
  const _HorizontalDragShield({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChatDrawerGestureGuard(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        onHorizontalDragCancel: () {},
        child: child,
      ),
    );
  }
}

class _DiffViewerColors {
  const _DiffViewerColors({
    required this.fileSurface,
    required this.headerSurface,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.lineText,
    required this.contextText,
    required this.gutterText,
    required this.icon,
    required this.chipBackground,
    required this.chipBorder,
    required this.chipText,
    required this.addBackground,
    required this.addAccent,
    required this.removeBackground,
    required this.removeAccent,
    required this.hunkBackground,
    required this.hunkText,
    required this.metaBackground,
    required this.contextBackground,
  });

  final Color fileSurface;
  final Color headerSurface;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color lineText;
  final Color contextText;
  final Color gutterText;
  final Color icon;
  final Color chipBackground;
  final Color chipBorder;
  final Color chipText;
  final Color addBackground;
  final Color addAccent;
  final Color removeBackground;
  final Color removeAccent;
  final Color hunkBackground;
  final Color hunkText;
  final Color metaBackground;
  final Color contextBackground;

  static _DiffViewerColors resolve(BuildContext context) {
    if (context.isDarkTheme) {
      return const _DiffViewerColors(
        fileSurface: Color(0xFF0F1724),
        headerSurface: Color(0xFF111B2B),
        border: Color(0xFF223047),
        divider: Color(0xFF223047),
        textPrimary: Color(0xFFF1F5FB),
        textSecondary: Color(0xFF8FA4C2),
        lineText: Color(0xFFE6EDF3),
        contextText: Color(0xFFD7E0EC),
        gutterText: Color(0xFF6F809A),
        icon: Color(0xFF9FB1C8),
        chipBackground: Color(0xFF162033),
        chipBorder: Color(0xFF2A3A53),
        chipText: Color(0xFF9FB1C8),
        addBackground: Color(0xFF12311F),
        addAccent: Color(0xFF7EE787),
        removeBackground: Color(0xFF351D24),
        removeAccent: Color(0xFFFF7B72),
        hunkBackground: Color(0xFF162033),
        hunkText: Color(0xFFBFD0E8),
        metaBackground: Color(0xFF111B2B),
        contextBackground: Color(0xFF0F1724),
      );
    }
    return const _DiffViewerColors(
      fileSurface: Color(0xFFFFFFFF),
      headerSurface: Color(0xFFF6F8FA),
      border: Color(0xFFE3E7ED),
      divider: Color(0xFFE7EAF0),
      textPrimary: Color(0xFF24292F),
      textSecondary: Color(0xFF6E7781),
      lineText: Color(0xFF24292F),
      contextText: Color(0xFF57606A),
      gutterText: Color(0xFF8C959F),
      icon: Color(0xFF6E7781),
      chipBackground: Color(0xFFFFFFFF),
      chipBorder: Color(0xFFD8DEE6),
      chipText: Color(0xFF6E7781),
      addBackground: Color(0xFFEFFAEF),
      addAccent: Color(0xFF1A7F37),
      removeBackground: Color(0xFFFFEBE9),
      removeAccent: Color(0xFFCF222E),
      hunkBackground: Color(0xFFF1F6FD),
      hunkText: Color(0xFF57606A),
      metaBackground: Color(0xFFF6F8FA),
      contextBackground: Color(0xFFFFFFFF),
    );
  }
}
