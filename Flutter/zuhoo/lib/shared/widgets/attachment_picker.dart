import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/bos_tokens.dart';

/// A file picked from the camera, the gallery, or device storage —
/// unified so callers deal in one shape regardless of which the person chose.
class PickedAttachment {
  const PickedAttachment({required this.path, required this.name});

  final String path;
  final String name;
}

enum _AttachmentSource { camera, gallery, file }

/// Offers the three ways someone actually has a document on a phone: photograph
/// it now, pick a photo already taken, or choose a file already saved. Returns
/// null if they picked nothing.
Future<PickedAttachment?> pickAttachment(BuildContext context) async {
  final source = await showModalBottomSheet<_AttachmentSource>(
    context: context,
    builder: (context) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return null;

  switch (source) {
    case _AttachmentSource.camera:
      final image =
          await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
      return image == null
          ? null
          : PickedAttachment(path: image.path, name: image.name);
    case _AttachmentSource.gallery:
      final image = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      return image == null
          ? null
          : PickedAttachment(path: image.path, name: image.name);
    case _AttachmentSource.file:
      final file = await FilePicker.pickFile();
      if (file?.path == null) return null;
      return PickedAttachment(path: file!.path!, name: file.name);
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final bos = Theme.of(context).bos;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Add an attachment',
              style: TextStyle(
                color: bos.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, _AttachmentSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.pop(context, _AttachmentSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('Choose a file'),
            onTap: () => Navigator.pop(context, _AttachmentSource.file),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
