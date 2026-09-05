class MaterialSources {
  const MaterialSources({
    this.organizations = const <String>[],
    this.repositories = const <String>[],
  });

  final List<String> organizations;
  final List<String> repositories;

  List<String> get all => <String>[...organizations, ...repositories];

  factory MaterialSources.fromJson(Map<String, dynamic> json) {
    final rawOrgs = json['organizations'];
    final rawRepos = json['repositories'];
    return MaterialSources(
      organizations: rawOrgs is List
          ? rawOrgs
                .map((s) => s?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      repositories: rawRepos is List
          ? rawRepos
                .map((s) => s?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class MaterialCollection {
  const MaterialCollection({
    required this.code,
    required this.title,
    this.sources = const <String>[],
  });

  final String code;
  final String title;
  final List<String> sources;

  factory MaterialCollection.fromJson(Map<String, dynamic> json) {
    final rawSources = json['source'] ?? json['sources'];
    return MaterialCollection(
      code: json['code']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      sources: rawSources is List
          ? rawSources
                .map((s) => s?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'code': code,
    'title': title,
    'sources': sources,
  };
}

class MaterialFile {
  const MaterialFile({
    required this.name,
    required this.path,
    required this.url,
    this.source = '',
  });

  final String name;
  final String path;
  final String url;
  final String source;

  factory MaterialFile.fromJson(Map<String, dynamic> json) {
    return MaterialFile(
      name: json['name']?.toString().trim() ?? '',
      path: json['path']?.toString().trim() ?? '',
      url: json['url']?.toString().trim() ?? '',
      source: json['source']?.toString().trim() ?? '',
    );
  }
}

class MaterialCategory {
  const MaterialCategory({required this.name, required this.files});

  final String name;
  final List<MaterialFile> files;

  factory MaterialCategory.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return MaterialCategory(
      name: json['name']?.toString().trim() ?? '',
      files: rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map(
                  (item) => MaterialFile.fromJson(item.cast<String, dynamic>()),
                )
                .where((file) => file.name.isNotEmpty && file.url.isNotEmpty)
                .toList(growable: false)
          : const <MaterialFile>[],
    );
  }
}

class MaterialDetail {
  const MaterialDetail({
    required this.code,
    required this.title,
    required this.categories,
    this.sources = const <String>[],
  });

  final String code;
  final String title;
  final List<MaterialCategory> categories;
  final List<String> sources;

  factory MaterialDetail.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final rawSources = json['source'] ?? json['sources'];
    return MaterialDetail(
      code: json['code']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      categories: rawCategories is List
          ? rawCategories
                .whereType<Map>()
                .map(
                  (item) =>
                      MaterialCategory.fromJson(item.cast<String, dynamic>()),
                )
                .where((category) => category.files.isNotEmpty)
                .toList(growable: false)
          : const <MaterialCategory>[],
      sources: rawSources is List
          ? rawSources
                .map((s) => s?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }
}
