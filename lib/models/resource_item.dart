class ResourceItem {
  final int id;
  final int parentId;
  final String title;
  final String otherTitle; // translated title, empty if none exists for the selected language
  final bool isFolder;
  final String imageUrl;
  final String audioUrl;
  final int sortOrder;

  const ResourceItem({
    required this.id,
    required this.parentId,
    required this.title,
    required this.otherTitle,
    required this.isFolder,
    required this.imageUrl,
    required this.audioUrl,
    required this.sortOrder,
  });

  factory ResourceItem.fromJson(Map<String, dynamic> json) {
    return ResourceItem(
      id: json['id'] as int,
      parentId: json['parentId'] as int,
      title: json['title'] as String? ?? '',
      otherTitle: json['otherTitle'] as String? ?? '',
      isFolder: json['isFolder'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String? ?? '',
      audioUrl: json['audioUrl'] as String? ?? '',
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }
}
