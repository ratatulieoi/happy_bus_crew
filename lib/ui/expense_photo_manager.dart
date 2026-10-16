import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/report_attachment.dart';
import 'app_theme.dart';

/// Changes affect only the form draft. Saved files are never removed here.
class ExpensePhotoManager extends StatefulWidget {
  final String label;
  final ExpenseOwner owner;
  final List<ReportAttachment> photos;
  final ValueChanged<List<ReportAttachment>> onChanged;

  const ExpensePhotoManager({
    super.key,
    required this.label,
    required this.owner,
    required this.photos,
    required this.onChanged,
  });

  @override
  State<ExpensePhotoManager> createState() => _ExpensePhotoManagerState();
}

class _ExpensePhotoManagerState extends State<ExpensePhotoManager> {
  final _picker = ImagePicker();
  late final _photos = List<ReportAttachment>.of(widget.photos);
  bool _picking = false;
  String? _error;

  static Future<void> _cropToSquare(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;
      final oriented = img.bakeOrientation(decoded);
      final width = oriented.width;
      final height = oriented.height;
      if (width == height) return;
      final side = width < height ? width : height;
      final x = (width - side) ~/ 2;
      final y = (height - side) ~/ 2;
      final cropped =
          img.copyCrop(oriented, x: x, y: y, width: side, height: side);
      final encoded = img.encodeJpg(cropped, quality: 80);
      await file.writeAsBytes(encoded, flush: true);
    } catch (_) {}
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final List<XFile> picked;
      if (source == ImageSource.gallery) {
        picked = await _picker.pickMultiImage(
          maxWidth: 1440,
          maxHeight: 1440,
          imageQuality: 80,
        );
      } else {
        final image = await _picker.pickImage(
          source: source,
          maxWidth: 1440,
          maxHeight: 1440,
          imageQuality: 80,
        );
        if (image != null) {
          await _cropToSquare(image.path);
          picked = [image];
        } else {
          picked = [];
        }
      }
      if (!mounted || picked.isEmpty) return;
      setState(() => _photos.addAll(picked.map((image) =>
          ReportAttachment(filePath: image.path, owner: widget.owner))));
      widget.onChanged(List.of(_photos));
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Foto belum dapat diambil. Periksa izin kamera atau galeri.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _view(int index) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: Text('${widget.label} • Foto ${index + 1}')),
          body: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.file(File(_photos[index].filePath),
                  errorBuilder: (_, __, ___) =>
                      const Text('Foto tidak dapat dibuka.')),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_picking,
        child: AlertDialog(
          title: Text('Foto ${widget.label}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_photos.isEmpty)
                    const Text('Belum ada foto. Foto bersifat opsional.')
                  else ...[
                    Text('${_photos.length} foto'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 156,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) => SizedBox(
                          width: 128,
                          child: Stack(fit: StackFit.expand, children: [
                            Semantics(
                              button: true,
                              label: 'Lihat foto ${i + 1}',
                              child: InkWell(
                                onTap: _picking ? null : () => _view(i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(_photos[i].filePath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const ColoredBox(
                                            color: AppColors.canvas,
                                            child: Center(
                                                child: Icon(Icons
                                                    .broken_image_outlined)),
                                          )),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton.filled(
                                tooltip: 'Hapus foto ${i + 1}',
                                style: IconButton.styleFrom(
                                    backgroundColor: AppColors.ink,
                                    foregroundColor: Colors.white),
                                onPressed: _picking
                                    ? null
                                    : () {
                                        setState(() => _photos.removeAt(i));
                                        widget.onChanged(List.of(_photos));
                                      },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Keep the existing platform behavior: Linux has no camera.
                  if (!Platform.isLinux) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            _picking ? null : () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 20),
                        label: const Text('Kamera'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _picking ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 20),
                      label: const Text('Galeri'),
                    ),
                  ),
                  if (_picking) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _picking ? null : () => Navigator.pop(context),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
}
