class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timeIso,
    required this.category,
  });

  final int id;
  final String title;
  final String message;
  final String timeIso;
  final String category;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'timeIso': timeIso,
    'category': category,
  };

  static NotificationItem fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final parsedId = rawId is num ? rawId.toInt() : int.parse(rawId.toString());
    return NotificationItem(
      id: parsedId,
      title: (json['title'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      timeIso: (json['timeIso'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'general',
    );
  }
}
