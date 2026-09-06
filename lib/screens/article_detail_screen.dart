import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class ArticleDetailScreen extends StatefulWidget {
  final int articleId;
  const ArticleDetailScreen({super.key, required this.articleId});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool _loading = true;
  String _title = '';
  String _body = '';
  String? _pdfUrl;

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  Future<void> _loadArticle() async {
    try {
      final data = await ApiService.get('/content/articles/${widget.articleId}/');
      if (!mounted) return;
      final article = data['data'] as Map<String, dynamic>? ?? data;
      // Null on the articles that are body-only. When it is set, the PDF *is*
      // the article — the body on those is a one-line category label — so the
      // screen becomes the document rather than a text page with a file on it.
      final pdf = article['pdf_url'] as String?;
      setState(() {
        _title = article['title'] as String? ?? '';
        _body = _stripHtml(article['body'] as String? ?? '');
        _pdfUrl = (pdf != null && pdf.isNotEmpty) ? pdf : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'</p>\s*<p>'), '\n\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = _pdfUrl != null;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.chevron_left, color: context.colors.textPrimary, size: 28),
        ),
        // On a PDF article the title has nowhere else to go — the page under
        // it is the document, edge to edge.
        title: Text(
          isPdf && _title.isNotEmpty ? _title : 'Articles',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: context.colors.accentYellow))
          : isPdf
              ? _PdfDocument(url: _pdfUrl!)
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _body,
                        style: TextStyle(
                          fontSize: 16,
                          color: context.colors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}

/// The article's PDF, filling the whole screen under the app bar.
///
/// No frame, no "Attached PDF" header and no way out to another app: the
/// reader is meant to read it here, the way they would a text article. Pinch
/// zooms, and pdfrx already handles that.
class _PdfDocument extends StatelessWidget {
  final String url;

  const _PdfDocument({required this.url});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(url);

    if (uri == null) {
      return const _PdfMessage(text: 'This PDF link is not valid.');
    }

    return PdfViewer.uri(
      uri,
      params: PdfViewerParams(
        backgroundColor: colors.background,
        loadingBannerBuilder: (context, downloaded, total) => Center(
          child: CircularProgressIndicator(
            // Indeterminate until the server sends a length — a bar stuck at
            // zero reads as a hang.
            value: (total != null && total > 0) ? downloaded / total : null,
            color: colors.accentYellow,
          ),
        ),
        errorBannerBuilder: (context, error, stackTrace, documentRef) =>
            const _PdfMessage(text: 'The PDF could not be loaded.'),
      ),
    );
  }
}

/// A centred failure state. It offers no way to open the file elsewhere on
/// purpose — the document is not meant to leave the app.
class _PdfMessage extends StatelessWidget {
  final String text;

  const _PdfMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 40,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
