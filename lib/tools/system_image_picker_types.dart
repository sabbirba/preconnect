class SystemPickedImage {
  const SystemPickedImage({required this.bytes, required this.name, this.path});

  final List<int> bytes;
  final String name;
  final String? path;
}
