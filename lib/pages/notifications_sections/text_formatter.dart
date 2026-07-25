final _nonAlphaNumRegex = RegExp(r'[^a-z0-9]+');
final _multiSpaceRegex = RegExp(r'\s+');
final _leadingBulletRegex = RegExp(r'^[\-\*•]\s*');
final _trailingPunctRegex = RegExp(r'[\s\)\]\}\>,;.!?]+$');
final _urlRegex = RegExp(
  "(https?://|www\\.)[^\\s<>\"'\\)]+",
  caseSensitive: false,
);
final _brTagRegex = RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false);
final _closingPTagRegex = RegExp(r'</\s*p\s*>', caseSensitive: false);
final _openingPTagRegex = RegExp(r'<\s*p[^>]*>', caseSensitive: false);
final _closingBlockTagRegex = RegExp(
  r'</\s*(div|blockquote|li)\s*>',
  caseSensitive: false,
);
final _openingBlockTagRegex = RegExp(
  r'<\s*(div|blockquote|ul|ol|li)[^>]*>',
  caseSensitive: false,
);
final _inlineTagRegex = RegExp(
  r'</?\s*(b|strong|i|em|u)\s*>',
  caseSensitive: false,
);
final _anyTagRegex = RegExp(r'<[^>]+>');
final _letterDigitRegex = RegExp(r'([A-Za-z])(\d)');
final _digitLetterRegex = RegExp(r'(\d)([A-Z])');
final _trailingSpaceBeforeNewlineRegex = RegExp(r'[ \t]+\n');
final _repeatedSpaceRegex = RegExp(r'[ \t]{2,}');
final _chevronOnlyLineRegex = RegExp(r'^[<>‹›❮❯]+$');
final _publishDateLabelRegex = RegExp(
  r'^publish\s+date\s*:?\s*$',
  caseSensitive: false,
);
final _dateLikeRegex = RegExp(
  r'^[A-Za-z]{3,9}\s+\d{1,2}(st|nd|rd|th)?\,?\s+\d{4}.*$',
  caseSensitive: false,
);
final _embeddedLinksLabelRegex = RegExp(
  r'^embedded\s+page\s+links\s*:?\s*$',
  caseSensitive: false,
);
final _listLinePrefixRegex = RegExp(r'^([-*•]|\d+[.)])\s+');
final _sentenceEndRegex = RegExp(r'[.!?:]$');
final _extraBlankLinesRegex = RegExp(r'\n{3,}');

String _normalizeCompareText(String value) {
  return value
      .toLowerCase()
      .replaceAll(_nonAlphaNumRegex, ' ')
      .replaceAll(_multiSpaceRegex, ' ')
      .trim();
}

String _sanitizeUrlCandidate(String value) {
  return value
      .trim()
      .replaceAll(_leadingBulletRegex, '')
      .replaceAll(_trailingPunctRegex, '')
      .replaceAll(_multiSpaceRegex, '');
}

String _normalizeUrlCandidate(String value) {
  return _sanitizeUrlCandidate(value);
}

String cleanNotificationBodyText(String raw, {String? title}) {
  if (raw.trim().isEmpty) return '';

  final protectedUrls = <String>[];
  final protectedRaw = raw.replaceAllMapped(_urlRegex, (match) {
    final token = '__PC_URL_${protectedUrls.length}__';
    protectedUrls.add(_normalizeUrlCandidate(match.group(0)!));
    return token;
  });

  var text = protectedRaw
      .replaceAll(_brTagRegex, '\n')
      .replaceAll(_closingPTagRegex, '\n\n')
      .replaceAll(_openingPTagRegex, '')
      .replaceAll(_closingBlockTagRegex, '\n')
      .replaceAll(_openingBlockTagRegex, '')
      .replaceAll(_inlineTagRegex, '')
      .replaceAll(_anyTagRegex, '');

  const htmlEntities = <String, String>{
    '&nbsp;': ' ',
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
  };
  htmlEntities.forEach((key, value) {
    text = text.replaceAll(key, value);
  });

  for (var i = 0; i < protectedUrls.length; i++) {
    text = text.replaceAll('__PC_URL_${i}__', protectedUrls[i]);
  }

  text = text
      .replaceAllMapped(
        _letterDigitRegex,
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAllMapped(
        _digitLetterRegex,
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(_trailingSpaceBeforeNewlineRegex, '\n')
      .replaceAll(_repeatedSpaceRegex, ' ')
      .trim();

  final normalizedTitle = _normalizeCompareText(title ?? '');
  final lines = text.split('\n');
  final kept = <String>[];
  final embeddedLinks = <String>[];
  var skipNextIfDateLike = false;
  var inEmbeddedLinksBlock = false;

  bool isUrl(String value) {
    return value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('www.');
  }

  bool isListLine(String value) {
    return _listLinePrefixRegex.hasMatch(value);
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      if (kept.isNotEmpty && kept.last.isNotEmpty) {
        kept.add('');
      }
      continue;
    }

    if (_chevronOnlyLineRegex.hasMatch(line)) continue;
    if (_normalizeCompareText(line) == normalizedTitle &&
        normalizedTitle.isNotEmpty) {
      continue;
    }
    if (_publishDateLabelRegex.hasMatch(line)) {
      skipNextIfDateLike = true;
      continue;
    }
    if (skipNextIfDateLike) {
      final isDateLike = _dateLikeRegex.hasMatch(line);
      skipNextIfDateLike = false;
      if (isDateLike) continue;
    }
    if (_embeddedLinksLabelRegex.hasMatch(line)) {
      inEmbeddedLinksBlock = true;
      continue;
    }

    final maybeUrl = _normalizeUrlCandidate(line);
    if (inEmbeddedLinksBlock && isUrl(maybeUrl)) {
      embeddedLinks.add(maybeUrl);
      continue;
    }
    if (inEmbeddedLinksBlock && !isUrl(line)) {
      inEmbeddedLinksBlock = false;
    }

    if (isUrl(maybeUrl)) continue;
    kept.add(line);
  }

  final blocks = <String>[];
  var paragraph = StringBuffer();

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(paragraph.toString().trim());
    paragraph = StringBuffer();
  }

  for (final line in kept) {
    if (line.isEmpty) {
      flushParagraph();
      continue;
    }

    if (line.endsWith(':') || isListLine(line)) {
      flushParagraph();
      final normalizedList = isListLine(line)
          ? line.replaceFirst(_listLinePrefixRegex, '- ')
          : line;
      if (blocks.isNotEmpty && blocks.last.startsWith('- ')) {
        blocks[blocks.length - 1] = '${blocks.last}\n$normalizedList';
      } else {
        blocks.add(normalizedList);
      }
      continue;
    }

    if (paragraph.isEmpty) {
      paragraph.write(line);
      continue;
    }

    final current = paragraph.toString().trimRight();
    if (_sentenceEndRegex.hasMatch(current)) {
      flushParagraph();
      paragraph.write(line);
    } else {
      paragraph.write(' $line');
    }
  }
  flushParagraph();

  if (embeddedLinks.isNotEmpty) {
    final linkLines = <String>['Source links:'];
    for (final link in embeddedLinks) {
      linkLines.add('- $link');
    }
    blocks.add(linkLines.join('\n'));
  }

  return blocks.join('\n\n').replaceAll(_extraBlankLinesRegex, '\n\n').trim();
}

class NotificationBodyParts {
  const NotificationBodyParts({required this.body, required this.links});

  final String body;
  final List<String> links;
}

NotificationBodyParts splitNotificationBodyParts(String cleaned) {
  if (cleaned.trim().isEmpty) {
    return const NotificationBodyParts(body: '', links: <String>[]);
  }

  final lines = cleaned.split('\n');
  final bodyLines = <String>[];
  final links = <String>[];
  var inSourceLinks = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      if (!inSourceLinks) bodyLines.add('');
      continue;
    }

    if (line.toLowerCase() == 'source links:') {
      inSourceLinks = true;
      continue;
    }

    if (inSourceLinks) {
      final extracted = _normalizeUrlCandidate(line);
      if (extracted.startsWith('http://') ||
          extracted.startsWith('https://') ||
          extracted.startsWith('www.')) {
        links.add(extracted);
        continue;
      }
      inSourceLinks = false;
    }

    bodyLines.add(rawLine);
  }

  final body = bodyLines
      .join('\n')
      .replaceAll(_extraBlankLinesRegex, '\n\n')
      .trim();
  return NotificationBodyParts(body: body, links: links);
}

String displayLinkLabel(String url) {
  return _normalizeUrlCandidate(url);
}
