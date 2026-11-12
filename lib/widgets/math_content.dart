import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class _LatexToken {
  const _LatexToken(this.start, this.end, this.source);

  final int start;
  final int end;
  final String source;
}

/// Renders model text containing lightweight Markdown and common LaTeX.
///
/// This local renderer handles the formatting normally emitted by the
/// question-solving models: headings, lists, rules, quotes, code, links,
/// simple tables, and inline/display LaTeX.
class MathContent extends StatelessWidget {
  const MathContent({
    super.key,
    required this.content,
    this.selectable = false,
  });

  final String content;
  final bool selectable;

  // Protected markers distinguish formula blocks assembled by this renderer
  // from unreliable `$$` tokens supplied by a model. They are converted back
  // only after all bare-line normalization is complete.
  static const _mathBlockStart = '\uE000';
  static const _mathBlockEnd = '\uE001';

  static final _displayPattern = RegExp(
    r'(\$\$[\s\S]+?\$\$|(?<!\\)\\\[[\s\S]+?(?<!\\)\\\])',
  );
  static final _inlinePattern = RegExp(r'(\$[^$\n]+?\$|\\\([\s\S]+?\\\))');
  static final _chineseCharacterPattern = RegExp(r'[\u4e00-\u9fff]');
  static final _headingPattern = RegExp(r'^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$');
  static final _unorderedPattern = RegExp(r'^\s*[-*+]\s+(.+)$');
  static final _orderedPattern = RegExp(r'^\s*(\d+)[.)]\s+(.+)$');
  static final _quotePattern = RegExp(r'^\s*>\s?(.*)$');
  static final _inlineMarkdownPattern = RegExp(
    r'(\*\*[\s\S]+?\*\*|__[\s\S]+?__|~~[\s\S]+?~~|`[^`\n]+`|\[[^\]\n]+\]\([^)]*\))',
  );
  static final _latexCommandPattern = RegExp(r'\\[a-zA-Z]+');
  static final _latexCommands = <String>{
    'alpha',
    'approx',
    'beta',
    'begin',
    'boxed',
    'cdot',
    'cos',
    'dfrac',
    'delta',
    'dot',
    'frac',
    'gamma',
    'ge',
    'geq',
    'infty',
    'int',
    'Longleftrightarrow',
    'lambda',
    'ldots',
    'le',
    'left',
    'leq',
    'mathrm',
    'mathbf',
    'mathbb',
    'mathit',
    'mu',
    'in',
    'neq',
    'omega',
    'operatorname',
    'overline',
    'partial',
    'pi',
    'pm',
    'quad',
    'qquad',
    'right',
    'rho',
    'sin',
    'sqrt',
    'sum',
    'tau',
    'text',
    'textbf',
    'theta',
    'times',
    'tfrac',
    'underline',
    'vec',
    'vdots',
    'end',
    'displaystyle',
  };

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(height: 1.55);
    // Some OpenAI-compatible gateways serialise Markdown/TeX one extra time
    // (for example `\\\\begin{bmatrix}`, `\\\\$I_2\\\\$`, and
    // `\\\\#\\\\# title`). Restore the syntax before parsing it.
    // TeX row breaks (`\\\\[4pt]`) are preserved.
    final normalized = _materializeMathBlocks(
      _normalizeBareMathLines(
        _normalizeMultilineLatex(
          _removeOrphanDisplayDelimiters(
            _removeMalformedEnvironmentDisplayStarts(
              _removeEquationTags(_normalizeEscapedModelSyntax(content)),
            ),
          ),
        ),
      ),
    );
    final parts = <Widget>[];
    var cursor = 0;
    for (final match in _displayPattern.allMatches(normalized)) {
      if (match.start > cursor) {
        parts.addAll(
            _markdownBlocks(normalized.substring(cursor, match.start), style));
      }
      parts.add(_displayMath(_stripDelimiter(match.group(0)!), style));
      cursor = match.end;
    }
    if (cursor < normalized.length) {
      parts.addAll(_markdownBlocks(normalized.substring(cursor), style));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: parts);
  }

  List<Widget> _markdownBlocks(String value, TextStyle style) {
    final lines =
        value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final widgets = <Widget>[];
    final codeLines = <String>[];
    var inCode = false;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        if (inCode) {
          widgets.add(_codeBlock(codeLines.join('\n'), style));
          codeLines.clear();
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeLines.add(line);
        continue;
      }
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (_isTableStart(lines, index)) {
        final table = <List<String>>[_splitTableRow(line)];
        index += 2;
        while (index < lines.length && _looksLikeTableRow(lines[index])) {
          table.add(_splitTableRow(lines[index]));
          index++;
        }
        index--;
        widgets.add(_tableBlock(table, style));
        continue;
      }

      final heading = _headingPattern.firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final headingStyle = style.copyWith(
          fontSize: (style.fontSize ?? 16) + (level <= 2 ? 4 : 2),
          fontWeight: FontWeight.w700,
          height: 1.35,
        );
        widgets.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 10 : 6, bottom: 4),
          child: _inlineText(heading.group(2)!.trim(), headingStyle),
        ));
        continue;
      }
      if (_isHorizontalRule(trimmed)) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 7),
          child: Divider(height: 1),
        ));
        continue;
      }

      final unordered = _unorderedPattern.firstMatch(line);
      if (unordered != null) {
        widgets.add(
            _listLine(marker: '•', value: unordered.group(1)!, style: style));
        continue;
      }
      final ordered = _orderedPattern.firstMatch(line);
      if (ordered != null) {
        widgets.add(_listLine(
            marker: '${ordered.group(1)}.',
            value: ordered.group(2)!,
            style: style));
        continue;
      }
      final quote = _quotePattern.firstMatch(line);
      if (quote != null) {
        widgets.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.only(left: 10),
          decoration: const BoxDecoration(
            border:
                Border(left: BorderSide(color: Color(0xffd39b6a), width: 3)),
          ),
          child: _inlineText(
              quote.group(1)!, style.copyWith(color: Colors.white70)),
        ));
        continue;
      }
      widgets.add(_inlineText(_unescapeMarkdown(line), style));
    }
    if (inCode && codeLines.isNotEmpty) {
      widgets.add(_codeBlock(codeLines.join('\n'), style));
    }
    return widgets;
  }

  Widget _listLine({
    required String marker,
    required String value,
    required TextStyle style,
  }) =>
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: marker == '•' ? 18 : 27,
                child: Text(marker, style: style)),
            Expanded(child: _inlineText(_unescapeMarkdown(value), style)),
          ],
        ),
      );

  Widget _codeBlock(String value, TextStyle style) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: SelectableText(value,
            style: style.copyWith(
                fontFamily: 'monospace', color: Colors.white70, height: 1.4)),
      );

  Widget _tableBlock(List<List<String>> rows, TextStyle style) {
    final columnCount = rows.fold<int>(
        0, (count, row) => row.length > count ? row.length : count);
    if (columnCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: Colors.white24, width: .7),
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
              TableRow(
                decoration: rowIndex == 0
                    ? const BoxDecoration(color: Color(0x1ad39b6a))
                    : null,
                children: [
                  for (var column = 0; column < columnCount; column++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: _inlineText(
                        column < rows[rowIndex].length
                            ? rows[rowIndex][column]
                            : '',
                        style.copyWith(
                            fontWeight: rowIndex == 0 ? FontWeight.w700 : null),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _inlineText(String value, TextStyle style) {
    final children = <InlineSpan>[];
    var cursor = 0;
    while (cursor < value.length) {
      final explicit = _nextMatch(_inlinePattern, value, cursor);
      final bare = _findBareLatex(value, cursor);
      if (explicit == null && bare == null) break;
      if (explicit != null && (bare == null || explicit.start <= bare.start)) {
        if (explicit.start > cursor) {
          _addMarkdownSpans(
              value.substring(cursor, explicit.start), style, children);
        }
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _inlineMath(_stripDelimiter(explicit.group(0)!), style),
        ));
        cursor = explicit.end;
      } else {
        if (bare!.start > cursor) {
          _addMarkdownSpans(
              value.substring(cursor, bare.start), style, children);
        }
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _inlineMath(bare.source, style),
        ));
        cursor = bare.end;
      }
    }
    if (cursor < value.length) {
      _addMarkdownSpans(value.substring(cursor), style, children);
    }
    if (children.isEmpty) children.add(const TextSpan(text: ''));
    if (selectable && children.every((child) => child is TextSpan)) {
      return SelectableText.rich(TextSpan(style: style, children: children));
    }
    return RichText(text: TextSpan(style: style, children: children));
  }

  RegExpMatch? _nextMatch(RegExp pattern, String value, int start) {
    for (final match in pattern.allMatches(value)) {
      if (match.start >= start) return match;
    }
    return null;
  }

  /// Finds an undelimited LaTeX fragment such as
  /// `电流为 i_C=\\frac{u}{R}`. Models often omit `$...$` around these
  /// fragments, which used to expose every LaTeX command as raw text.
  _LatexToken? _findBareLatex(String value, int start) {
    for (final command in _latexCommandPattern.allMatches(value)) {
      if (command.start < start) continue;
      final name = command.group(0)!.substring(1);
      if (!_latexCommands.contains(name)) continue;

      var tokenStart = _bareMathStart(value, command.start);
      var tokenEnd = _bareMathEnd(value, command.start);
      if (tokenEnd <= command.end) continue;
      var source = value.substring(tokenStart, tokenEnd).trim();

      // Do not consume an English sentence before a standalone command such
      // as "please use \\frac". Preserve the equation prefix only when it
      // contains an unmistakable mathematical relation or sub/superscript.
      if (tokenStart < command.start &&
          !RegExp(r'[=_^{}]')
              .hasMatch(source.substring(0, command.start - tokenStart))) {
        tokenStart = command.start;
        source = value.substring(tokenStart, tokenEnd).trim();
      }
      if (_looksLikeLatex(source)) {
        return _LatexToken(tokenStart, tokenEnd, source);
      }
    }
    return null;
  }

  int _bareMathStart(String value, int commandStart) {
    var index = commandStart;
    while (index > 0) {
      final previous = value[index - 1];
      if (_isBareMathCharacter(previous)) {
        index--;
        continue;
      }
      if (previous.trim().isEmpty &&
          index > 1 &&
          _isBareMathCharacter(value[index - 2])) {
        index--;
        continue;
      }
      break;
    }
    return index;
  }

  int _bareMathEnd(String value, int commandStart) {
    var index = commandStart;
    while (index < value.length) {
      final character = value[index];
      if (_isChinese(character) || character == r'$' || character == '`') {
        break;
      }
      if (character == '\\') {
        final command = _latexCommandPattern.matchAsPrefix(value, index);
        if (command != null) {
          index = command.end;
        } else if (index + 1 < value.length &&
            RegExp(r'[,;:!]').hasMatch(value[index + 1])) {
          // TeX spacing commands such as \, and \! are part of the
          // expression even though they have no alphabetic command name.
          index += 2;
        } else {
          break;
        }
        while (index < value.length && value[index].trim().isEmpty) index++;
        while (index < value.length && _isLatexGroupStart(value[index])) {
          index = _consumeLatexGroup(value, index);
          while (index < value.length && value[index].trim().isEmpty) index++;
        }
        continue;
      }
      if (_isLatexGroupStart(character)) {
        index = _consumeLatexGroup(value, index);
        continue;
      }
      if (character.trim().isEmpty) break;
      if (!_isBareMathCharacter(character) || character == ',') {
        break;
      }
      index++;
    }
    return index;
  }

  int _consumeLatexGroup(String value, int start) {
    final opening = value[start];
    final closing = opening == '{'
        ? '}'
        : opening == '('
            ? ')'
            : ']';
    var depth = 0;
    for (var index = start; index < value.length; index++) {
      if (value[index] == opening) depth++;
      if (value[index] == closing) {
        depth--;
        if (depth == 0) return index + 1;
      }
    }
    return value.length;
  }

  bool _isLatexGroupStart(String value) =>
      value == '{' || value == '(' || value == '[';

  bool _isBareMathCharacter(String value) =>
      RegExp(r'[A-Za-z0-9_{}^=+\-*/().:;<>\[\]|]').hasMatch(value);

  bool _isChinese(String value) => _chineseCharacterPattern.hasMatch(value);

  bool _looksLikeLatex(String source) =>
      _latexCommandPattern.hasMatch(source) && source.trim().length > 2;

  void _addMarkdownSpans(
      String value, TextStyle style, List<InlineSpan> children) {
    var cursor = 0;
    for (final match in _inlineMarkdownPattern.allMatches(value)) {
      if (match.start > cursor)
        children.add(TextSpan(text: value.substring(cursor, match.start)));
      final token = match.group(0)!;
      if ((token.startsWith('**') && token.endsWith('**')) ||
          (token.startsWith('__') && token.endsWith('__'))) {
        children.add(TextSpan(
            text: token.substring(2, token.length - 2),
            style: style.copyWith(fontWeight: FontWeight.w700)));
      } else if (token.startsWith('~~') && token.endsWith('~~')) {
        children.add(TextSpan(
            text: token.substring(2, token.length - 2),
            style: style.copyWith(decoration: TextDecoration.lineThrough)));
      } else if (token.startsWith('`') && token.endsWith('`')) {
        children.add(TextSpan(
            text: token.substring(1, token.length - 1),
            style: style.copyWith(
                fontFamily: 'monospace', color: const Color(0xffffcc99))));
      } else if (token.startsWith('[')) {
        final close = token.indexOf(']');
        children.add(TextSpan(
            text: token.substring(1, close),
            style: style.copyWith(
                color: const Color(0xffe5b47e),
                decoration: TextDecoration.underline)));
      } else {
        children.add(TextSpan(text: token));
      }
      cursor = match.end;
    }
    if (cursor < value.length)
      children.add(TextSpan(text: value.substring(cursor)));
  }

  Widget _inlineMath(String source, TextStyle style) => Math.tex(
        source,
        mathStyle: MathStyle.text,
        textStyle: style,
        onErrorFallback: (_) => Text(source,
            style: style.copyWith(fontFamily: 'monospace'), softWrap: true),
      );

  Widget _displayMath(String source, TextStyle style) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            source,
            mathStyle: MathStyle.display,
            textStyle: style.copyWith(fontSize: (style.fontSize ?? 16) + 2),
            onErrorFallback: (_) => Text(source,
                style: style.copyWith(fontFamily: 'monospace'), softWrap: true),
          ),
        ),
      );

  String _normalizeMultilineLatex(String value) {
    final lines =
        value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final normalized = <String>[];
    var inCode = false;
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        inCode = !inCode;
        normalized.add(line);
        index++;
        continue;
      }
      final trimmedStart = line.indexOf(trimmed);
      final mathStartInTrimmed = _multilineMathStartIndex(trimmed);
      final mathStart =
          mathStartInTrimmed < 0 ? -1 : trimmedStart + mathStartInTrimmed;
      if (!inCode && mathStart >= 0) {
        // A model can open a display delimiter on the preceding line and
        // start `\\boxed`/`\\begin{cases}` on the following line. The full
        // construct is promoted to one display block below, so discard the
        // outer marker before it can pair with a stray later delimiter.
        if (normalized.isNotEmpty &&
            _isStandaloneMathDelimiter(normalized.last.trim())) {
          normalized.removeLast();
        }
        if (mathStart > 0) {
          final prefix = line.substring(0, mathStart);
          if (!_isMathDelimiterPrefix(prefix)) {
            normalized.add(prefix);
          }
        }
        final block = <String>[];
        var groupDepth = 0;
        var environmentDepth = 0;
        var delimiterDepth = 0;
        var end = index;
        for (; end < lines.length; end++) {
          final blockLine = lines[end];
          final mathLine =
              end == index ? blockLine.substring(mathStart) : blockLine;
          block.add(mathLine);
          groupDepth += _braceDelta(mathLine);
          environmentDepth += _countCommands(mathLine, r'\begin') -
              _countCommands(mathLine, r'\end');
          delimiterDepth += _countCommands(mathLine, r'\left') -
              _countCommands(mathLine, r'\right');
          // A complete `bmatrix`, `cases`, or `boxed` expression can occupy
          // one physical line. Finish it immediately instead of consuming
          // the next line (which may be the beginning of another matrix).
          // Incomplete openers such as `\boxed{` still stay open because
          // their group depth is positive.
          if (groupDepth <= 0 && environmentDepth <= 0) {
            break;
          }
        }
        final complete = end < lines.length &&
            groupDepth <= 0 &&
            environmentDepth <= 0;
        if (complete) {
          normalized
            ..add(_mathBlockStart)
            // Some models put each row of a boxed/cases expression in its
            // own `$...$`, `$$...$$`, `\\(...\\)`, or `\\[...\\]`
            // delimiter.  This expression is already being promoted to one
            // display block, so retaining those nested delimiters makes the
            // display-regex split the outer formula at the first inner `$$`.
            // The result was exactly the mixed raw `\\boxed{` + partly
            // rendered output seen in the solver UI.
            ..addAll(_removeNestedMathDelimiters(block))
            ..add(_mathBlockEnd);
          index = _skipFollowingMathDelimiter(lines, end + 1);
          continue;
        }
        // A streamed response can end in the middle of a formula. Keep the
        // entire partial block together and close the constructs that are
        // safe to close synthetically. Otherwise the fallback line parser
        // would expose commands such as \boxed and \begin{cases} as text.
        if (end >= lines.length && block.length > 1) {
          normalized
            ..add(_mathBlockStart)
            ..addAll(_removeNestedMathDelimiters(
              _repairIncompleteLatexBlock(
                block,
                groupDepth: groupDepth,
                environmentDepth: environmentDepth,
                delimiterDepth: delimiterDepth,
              ),
            ))
            ..add(_mathBlockEnd);
          index = lines.length;
          continue;
        }
      }
      normalized.add(line);
      index++;
    }
    return normalized.join('\n');
  }

  /// Removes delimiters nested inside a multiline LaTex construct.
  ///
  /// `flutter_math_fork` receives the whole construct as TeX. Dollar
  /// delimiters are Markdown syntax, not TeX syntax, and must not remain
  /// inside it. Keep escaped dollar signs intact because they are literal TeX
  /// content. Do not strip `\\[6pt]`: in a `cases` environment it is the
  /// normal TeX row-spacing command, not a Markdown delimiter.
  List<String> _removeNestedMathDelimiters(List<String> lines) => lines
      .map(
        (line) {
          final trimmed = line.trim();
          if (trimmed == r'\[' || trimmed == r'\]') return '';
          return line
              .replaceAll(r'$$', '')
              .replaceAllMapped(
                RegExp(r'(?<!\\)\$'),
                (_) => '',
              );
        },
      )
      .toList();

  bool _isStandaloneMathDelimiter(String value) =>
      value == r'$' ||
      value == r'$$' ||
      value == r'\\[' ||
      value == r'\\]' ||
      value == r'\\(' ||
      value == r'\\)';

  int _skipFollowingMathDelimiter(List<String> lines, int index) {
    if (index < lines.length &&
        _isStandaloneMathDelimiter(lines[index].trim())) {
      return index + 1;
    }
    return index;
  }

  String _normalizeBareMathLines(String value) {
    final lines = value.split('\n');
    final normalized = <String>[];
    var inDisplay = false;
    var inProtectedBlock = false;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trim();
      if (trimmed == _mathBlockStart) {
        inProtectedBlock = true;
        normalized.add(line);
        continue;
      }
      if (trimmed == _mathBlockEnd) {
        inProtectedBlock = false;
        normalized.add(line);
        continue;
      }
      if (inProtectedBlock) {
        normalized.add(line);
        continue;
      }
      final displayDelimiterCount = _displayDelimiterCount(trimmed);
      if (trimmed == r'$$') {
        // Environment normalization writes a standalone pair around every
        // promoted block. Pair these only when they enclose ordinary text;
        // if the next nonblank line starts a TeX environment, leave that
        // block to the existing environment parser instead.
        var next = index + 1;
        while (next < lines.length && lines[next].trim().isEmpty) next++;
        final nextStartsEnvironment = next < lines.length &&
            _multilineMathStartIndex(lines[next].trim()) >= 0;
        if (!nextStartsEnvironment) inDisplay = !inDisplay;
        normalized.add(line);
        continue;
      }
      if (displayDelimiterCount >= 2) {
        // A one-line display formula contains two delimiters and must not
        // leave the following content in display mode. The old startsWith
        // check toggled once in this case, which made later matrices, boxed
        // formulas, and inline `$Y$` text fall through as raw source.
        if (displayDelimiterCount.isOdd) inDisplay = !inDisplay;
        normalized.add(line);
        continue;
      }
      // A single `$$` cannot delimit a complete formula. Keep it as a normal
      // line so malformed model output cannot put all later content into an
      // unterminated display state.
      if (displayDelimiterCount == 1) {
        // Strip a stray delimiter from an otherwise bare matrix/boxed
        // expression and then let the environment normalizer wrap the whole
        // construct. Keeping it here would make the later display-regex pair
        // this line with an unrelated `$$`.
        final withoutDelimiter = line.replaceFirst(RegExp(r'(?<!\\)\$\$'), '');
        final startsFormula = _multilineMathStartIndex(withoutDelimiter.trim()) >= 0;
        if (startsFormula) {
          if (withoutDelimiter.trim().isNotEmpty) normalized.add(withoutDelimiter);
          continue;
        }
        normalized.add(line);
        continue;
      }
      if (_hasBracketDisplayDelimiter(trimmed)) {
        inDisplay = !inDisplay;
        normalized.add(line);
        continue;
      }
      if (inDisplay) {
        normalized.add(line);
        continue;
      }
      final isMarkdownLine = trimmed.startsWith('#') ||
          _unorderedPattern.hasMatch(trimmed) ||
          _orderedPattern.hasMatch(trimmed) ||
          _quotePattern.hasMatch(trimmed) ||
          trimmed.startsWith('```') ||
          trimmed.contains('|') ||
          _isHorizontalRule(trimmed);
      final isPlainAlgebraLine = !_chineseCharacterPattern.hasMatch(trimmed) &&
          !trimmed.endsWith('=') &&
          RegExp(r'[=_^]').hasMatch(trimmed) &&
          RegExp(r'[A-Za-z0-9(){}^_=+\-*/.,<>| ]+$').hasMatch(trimmed);
      final isBareFormula = trimmed.isNotEmpty &&
          !isMarkdownLine &&
          (_latexCommandPattern.hasMatch(trimmed) || isPlainAlgebraLine) &&
          !_chineseCharacterPattern.hasMatch(trimmed) &&
          !trimmed.contains(r'$') &&
          !trimmed.contains(r'\(') &&
          !trimmed.contains(r'\[');
      normalized.add(isBareFormula ? r'$$' + trimmed + r'$$' : line);
    }
    return normalized.join('\n');
  }

  String _materializeMathBlocks(String value) => value
      .replaceAll(_mathBlockStart, r'$$')
      .replaceAll(_mathBlockEnd, r'$$');

  int _displayDelimiterCount(String value) =>
      RegExp(r'(?<!\\)\$\$').allMatches(value).length;

  bool _hasBracketDisplayDelimiter(String value) =>
      value == r'\[' || value == r'\]';

  /// Restores Markdown/TeX syntax that an API gateway escaped one extra
  /// time. Brackets and parentheses are intentionally excluded: `\\[...\\]`
  /// and `\\(...\\)` are valid TeX delimiters, while `\\\\[4pt]` is a
  /// valid matrix/cases row break and spacing command.
  String _normalizeEscapedModelSyntax(String value) {
    final markdownRestored = value.replaceAllMapped(
      RegExp(r'\\+([#$*_\-])'),
      (match) => match.group(1)!,
    );
    return markdownRestored.replaceAllMapped(
      RegExp(r'\\{2,}(?=[A-Za-z])'),
      (_) => '\\',
    );
  }

  /// `flutter_math_fork` supports matrices but not KaTeX's equation tagging
  /// extension. A tag is presentation-only here, so remove it rather than
  /// allowing a valid equation to fall back to raw source text.
  String _removeEquationTags(String value) => value.replaceAll(
        RegExp(r'\\tag\*?\s*\{[^{}\n]*\}'),
        '',
      );

  /// Discards only the final unmatched `$$` emitted by a model. It cannot
  /// form a display formula, but previously switched the line normalizer into
  /// a permanent display state and suppressed rendering of everything after
  /// it. Complete delimiter pairs are preserved unchanged.
  String _removeOrphanDisplayDelimiters(String value) {
    final matches = RegExp(r'(?<!\\)\$\$').allMatches(value).toList();
    if (matches.length.isEven || matches.isEmpty) return value;
    final orphan = matches.last;
    return value.substring(0, orphan.start) + value.substring(orphan.end);
  }

  /// Models occasionally prefix a complete one-line matrix or boxed formula
  /// with `$$` but omit its matching closing delimiter. The next `$$` then
  /// incorrectly closes that formula and leaves all following TeX in a
  /// display-mode limbo. Remove only this malformed prefix; the environment
  /// normalizer wraps the complete formula with a correct delimiter pair.
  String _removeMalformedEnvironmentDisplayStarts(String value) {
    final lines = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final normalized = <String>[];
    for (var index = 0; index < lines.length; index++) {
      var line = lines[index];
      final malformedStart = RegExp(
        r'^(\s*)\$\$(?=\s*\\(?:begin|boxed)\{)',
      ).hasMatch(line) &&
          _displayDelimiterCount(line) == 1;
      if (malformedStart) line = line.replaceFirst(RegExp(r'^\s*\$\$'), '');
      normalized.add(line);

      // A malformed opening delimiter is frequently followed by the next
      // formula's valid `$$...$$` block. That first delimiter would otherwise
      // be mistaken for its closing mate, so remove it only when it occurs at
      // the beginning of the next nonblank line.
      if (malformedStart) {
        var next = index + 1;
        while (next < lines.length && lines[next].trim().isEmpty) next++;
        if (next < lines.length &&
            RegExp(r'^\s*\$\$').hasMatch(lines[next]) &&
            _displayDelimiterCount(lines[next]) >= 2) {
          lines[next] = lines[next].replaceFirst(RegExp(r'^\s*\$\$'), '');
        }
      }
    }
    return normalized.join('\n');
  }

  int _multilineMathStartIndex(String value) {
    final candidates = [
      value.indexOf(r'\boxed'),
      value.indexOf(r'\begin{'),
      value.indexOf(r'\left['),
      value.indexOf(r'\left\{'),
      value.indexOf(r'\left('),
    ].where((index) => index >= 0).toList();
    if (candidates.isEmpty) return -1;
    final start = candidates.reduce((a, b) => a < b ? a : b);
    // Do not consume an ordinary sentence that merely mentions a command.
    // A formula block must begin at the start of a line or after a clear
    // separator such as ':' or an opening parenthesis.
    if (start > 0 &&
        !RegExp(r'[:=(\[]\s*$').hasMatch(value.substring(0, start)) &&
        !_isMathDelimiterPrefix(value.substring(0, start))) {
      return -1;
    }
    return start;
  }

  bool _isMathDelimiterPrefix(String value) => RegExp(
        r'^\s*(?:\$\$?|\\\[|\\\()\s*$',
      ).hasMatch(value);

  int _braceDelta(String value) {
    var delta = 0;
    for (var index = 0; index < value.length; index++) {
      if (value[index] != '{' && value[index] != '}') continue;
      var slashCount = 0;
      for (var previous = index - 1;
          previous >= 0 && value[previous] == '\\';
          previous--) {
        slashCount++;
      }
      if (slashCount.isOdd) continue;
      delta += value[index] == '{' ? 1 : -1;
    }
    return delta;
  }

  int _countCommands(String value, String command) {
    var count = 0;
    var cursor = 0;
    while (cursor < value.length) {
      final found = value.indexOf(command, cursor);
      if (found < 0) break;
      count++;
      cursor = found + command.length;
    }
    return count;
  }

  List<String> _repairIncompleteLatexBlock(
    List<String> block, {
    required int groupDepth,
    required int environmentDepth,
    required int delimiterDepth,
  }) {
    final repaired = [...block];
    if (environmentDepth > 0) {
      // The supported multiline environment in the question solver is
      // cases. Keep this conservative so ordinary prose is never invented.
      final beginsCases = block.any((line) => line.contains(r'\begin{cases}'));
      if (beginsCases) repaired.add(r'\end{cases}');
    }
    if (delimiterDepth > 0) {
      var leftSquare = 0;
      var leftCurly = 0;
      var leftRound = 0;
      for (final line in block) {
        leftSquare +=
            _countCommands(line, r'\left[') - _countCommands(line, r'\right]');
        leftCurly += _countCommands(line, r'\left\{') -
            _countCommands(line, r'\right\}');
        leftRound +=
            _countCommands(line, r'\left(') - _countCommands(line, r'\right)');
      }
      if (leftSquare > 0) repaired.addAll(List.filled(leftSquare, r'\right]'));
      if (leftCurly > 0) repaired.addAll(List.filled(leftCurly, r'\right\}'));
      if (leftRound > 0) repaired.addAll(List.filled(leftRound, r'\right)'));
    }
    if (groupDepth > 0) {
      repaired.add('}' * groupDepth);
    }
    return repaired;
  }

  bool _isHorizontalRule(String value) =>
      RegExp(r'^\s*(?:---+|___+|\*\s*\*\s*\*.*?)\s*$').hasMatch(value);

  bool _isTableStart(List<String> lines, int index) =>
      index + 1 < lines.length &&
      _looksLikeTableRow(lines[index]) &&
      _isTableSeparator(lines[index + 1]);

  bool _looksLikeTableRow(String value) =>
      value.contains('|') && value.trim().isNotEmpty;

  bool _isTableSeparator(String value) => RegExp(
        r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$',
      ).hasMatch(value);

  List<String> _splitTableRow(String value) {
    var row = value.trim();
    if (row.startsWith('|')) row = row.substring(1);
    if (row.endsWith('|')) row = row.substring(0, row.length - 1);
    return row
        .split('|')
        .map((cell) => _unescapeMarkdown(cell.trim()))
        .toList();
  }

  String _unescapeMarkdown(String value) => value.replaceAllMapped(
      RegExp(r'\\([*_`#>\[\]])'), (match) => match.group(1)!);

  String _stripDelimiter(String source) {
    if (source.startsWith(r'$$') && source.endsWith(r'$$')) {
      return source.substring(2, source.length - 2).trim();
    }
    if (source.startsWith(r'\[') && source.endsWith(r'\]')) {
      return source.substring(2, source.length - 2).trim();
    }
    if (source.startsWith(r'\(') && source.endsWith(r'\)')) {
      return source.substring(2, source.length - 2).trim();
    }
    if (source.startsWith(r'$') && source.endsWith(r'$')) {
      return source.substring(1, source.length - 1).trim();
    }
    return source;
  }
}
