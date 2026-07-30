import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

/// The PDF attached to an article, read inside the app.
///
/// In-app rather than handed to the OS viewer because the attachment is part
/// of the article — a worksheet or the printed original — and bouncing the
/// reader out to Safari or a downloads folder loses their place in a way that
/// a back button does not.
///
/// [PdfViewer.uri] streams the file rather than downloading it whole first, so
/// a long handout starts rendering on page one instead of after the last byte.
/// The "open externally" action stays in the app bar for the two cases the
/// embedded viewer cannot serve: printing, and saving a copy.
class ArticlePdfScreen extends StatelessWidget {
  final String url;
  final String title;

  const ArticlePdfScreen({super.key, required this.url, required this.title});

  Future<void> _openExternally(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the PDF.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(url);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.chevron_left, color: colors.textPrimary, size: 28),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Open outside the app',
            onPressed: () => _openExternally(context),
            icon: Icon(Icons.open_in_new, color: colors.textPrimary, size: 22),
          ),
        ],
      ),
      body: uri == null
          ? _Message(
              text: 'This PDF link is not valid.',
              onRetry: null,
            )
          : PdfViewer.uri(
              uri,
              params: PdfViewerParams(
                backgroundColor: colors.background,
                loadingBannerBuilder: (context, downloaded, total) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        // Indeterminate until the server sends a length —
                        // a bar stuck at zero reads as a hang.
                        value: (total != null && total > 0)
                            ? downloaded / total
                            : null,
                        color: colors.accentYellow,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading PDF…',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                    _Message(
                      text: 'The PDF could not be loaded.',
                      onRetry: () => _openExternally(context),
                    ),
              ),
            ),
    );
  }
}

/// A centred failure state with one way forward — opening the file in whatever
/// the device already uses for PDFs, which usually succeeds where the embedded
/// renderer did not.
class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Message({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 44,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Open outside the app',
                  style: TextStyle(
                    color: colors.accentBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
