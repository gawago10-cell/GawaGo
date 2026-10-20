import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/gawago_api.dart';
import '../../core/theme/gawago_colors.dart';

/// An image served by a permission-checked API route (certificates,
/// verification documents). Image.network can't send the bearer token, so
/// the bytes are fetched with it and drawn from memory.
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    super.key,
    required this.url,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? height;
  final BoxFit fit;

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() =>
      GawaGoApi.getBytes(GawaGoApi.apiPath(widget.url));

  @override
  void didUpdateWidget(AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      setState(() {
        _bytes = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) {
          return Container(
            height: widget.height,
            color: GawaGoColors.surfaceMuted,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Shown in place of a thumbnail when the certificate is a PDF: the app has
/// no PDF viewer, so it points to where the file can be opened.
class CertificateFileNote extends StatelessWidget {
  const CertificateFileNote({super.key, required this.isPdf});

  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GawaGoColors.surfaceMuted,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.insert_drive_file_outlined,
            color: GawaGoColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPdf
                  ? 'PDF document — open it on the GawaGo website to view.'
                  : 'Document attached — open it on the GawaGo website to view.',
              style: const TextStyle(
                color: GawaGoColors.textMuted,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
