class BracuLeaksCollection {
  const BracuLeaksCollection({required this.code, required this.title});

  final String code;
  final String title;

  factory BracuLeaksCollection.fromJson(Map<String, dynamic> json) {
    return BracuLeaksCollection(
      code: json['code']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'title': title,
  };
}

class BracuLeaksFile {
  const BracuLeaksFile({
    required this.name,
    required this.path,
    required this.url,
  });

  final String name;
  final String path;
  final String url;

  factory BracuLeaksFile.fromJson(Map<String, dynamic> json) {
    return BracuLeaksFile(
      name: json['name']?.toString().trim() ?? '',
      path: json['path']?.toString().trim() ?? '',
      url: json['url']?.toString().trim() ?? '',
    );
  }
}

class BracuLeaksCategory {
  const BracuLeaksCategory({required this.name, required this.files});

  final String name;
  final List<BracuLeaksFile> files;

  factory BracuLeaksCategory.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return BracuLeaksCategory(
      name: json['name']?.toString().trim() ?? '',
      files: rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map(
                  (item) =>
                      BracuLeaksFile.fromJson(item.cast<String, dynamic>()),
                )
                .where((file) => file.name.isNotEmpty && file.url.isNotEmpty)
                .toList(growable: false)
          : const <BracuLeaksFile>[],
    );
  }
}

class BracuLeaksDetail {
  const BracuLeaksDetail({
    required this.code,
    required this.title,
    required this.categories,
  });

  final String code;
  final String title;
  final List<BracuLeaksCategory> categories;

  factory BracuLeaksDetail.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    return BracuLeaksDetail(
      code: json['code']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      categories: rawCategories is List
          ? rawCategories
                .whereType<Map>()
                .map(
                  (item) =>
                      BracuLeaksCategory.fromJson(item.cast<String, dynamic>()),
                )
                .where((category) => category.files.isNotEmpty)
                .toList(growable: false)
          : const <BracuLeaksCategory>[],
    );
  }
}
