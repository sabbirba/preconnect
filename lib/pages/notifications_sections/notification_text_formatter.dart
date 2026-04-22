String _normalizeCompareText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _sanitizeUrlCandidate(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'^[\-\*\u2022]\s*'), '')
      .replaceAll(RegExp(r'[\s\)\]\}\>,;.!?]+$'), '')
      .replaceAll(RegExp(r'\s+'), '');
}

String _normalizeUrlCandidate(String value) {
  return _sanitizeUrlCandidate(value);
}

String normalizeNotificationSourceUrl(String value) {
  return _normalizeUrlCandidate(value);
}

String cleanNotificationBodyText(String raw, {String? title}) {
  if (raw.trim().isEmpty) return '';

  final protectedUrls = <String>[];
  final protectedRaw = raw.replaceAllMapped(
    RegExp("(https?://|www\\.)[^\\s<>\"'\\)]+", caseSensitive: false),
    (match) {
      final token = '__PC_URL_${protectedUrls.length}__';
      protectedUrls.add(_normalizeUrlCandidate(match.group(0)!));
      return token;
    },
  );

  var text = protectedRaw
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<\s*p[^>]*>', caseSensitive: false), '')
      .replaceAll(
        RegExp(r'</\s*(div|blockquote|li)\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(
        RegExp(r'<\s*(div|blockquote|ul|ol|li)[^>]*>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'</?\s*(b|strong|i|em|u)\s*>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '');

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
        RegExp(r'([A-Za-z])(\d)'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'(\d)([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
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
    return RegExp(r'^([-*•]|\d+[.)])\s+').hasMatch(value);
  }

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      if (kept.isNotEmpty && kept.last.isNotEmpty) {
        kept.add('');
      }
      continue;
    }

    if (RegExp(r'^[<>‹›❮❯]+$').hasMatch(line)) continue;
    if (_normalizeCompareText(line) == normalizedTitle &&
        normalizedTitle.isNotEmpty) {
      continue;
    }
    if (RegExp(
      r'^publish\s+date\s*:?\s*$',
      caseSensitive: false,
    ).hasMatch(line)) {
      skipNextIfDateLike = true;
      continue;
    }
    if (skipNextIfDateLike) {
      final isDateLike = RegExp(
        r'^[A-Za-z]{3,9}\s+\d{1,2}(st|nd|rd|th)?\,?\s+\d{4}.*$',
        caseSensitive: false,
      ).hasMatch(line);
      skipNextIfDateLike = false;
      if (isDateLike) continue;
    }
    if (RegExp(
      r'^embedded\s+page\s+links\s*:?\s*$',
      caseSensitive: false,
    ).hasMatch(line)) {
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
          ? line.replaceFirst(RegExp(r'^([-*•]|\d+[.)])\s+'), '- ')
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
    if (RegExp(r'[.!?:]$').hasMatch(current)) {
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

  return blocks.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return NotificationBodyParts(body: body, links: links);
}

String displayLinkLabel(String url) {
  return _normalizeUrlCandidate(url);
}
