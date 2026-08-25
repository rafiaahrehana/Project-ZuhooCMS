/// `POST /api/upload` response (`FileUploadController` — 10MB effective cap,
/// content-type cross-checked server-side against the extension).
class UploadedFile {
  const UploadedFile({required this.fileName, required this.fileUrl});

  final String fileName;
  final String fileUrl;

  factory UploadedFile.fromJson(Map<String, dynamic> json) => UploadedFile(
        fileName: json['fileName'] as String? ?? '',
        fileUrl: json['fileUrl'] as String? ?? '',
      );
}
