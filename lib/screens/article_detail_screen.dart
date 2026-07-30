import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
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
      // Null on the articles that are body-only, which is most of them — the
      // attachment card only appears for the ones that carry a handout.
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
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.chevron_left, color: context.colors.textPrimary, size: 28),
        ),
        title: Text(
          'Articles',
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
                  // The handout opens here, on the article, rather than behind
                  // a card — on an article whose content *is* the PDF, a card
                  // is one more tap in front of the only thing on the page.
                  if (_pdfUrl != null) ...[
                    const SizedBox(height: 28),
                    _PdfSection(url: _pdfUrl!),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

/// The attached handout, rendered inline on the article.
///
/// Bounded rather than full-height: a fifty-page PDF laid out at its natural
/// length would bury the article under it and leave the outer scroll view with
/// nothing sensible to do. So the document scrolls inside its own box, the way
/// it does on the web.
///
/// No zoom buttons — pinch is the gesture here, and pdfrx already handles it.
/// The one action worth a button is leaving for the OS viewer, which is what
/// printing and saving a copy still need.
class _PdfSection extends StatelessWidget {
  final String url;

  const _PdfSection({required this.url});

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

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 18,
                  color: colors.accentBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Attached PDF',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open outside the app',
                  onPressed: () => _openExternally(context),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.7,
            child: uri == null
                ? _PdfMessage(
                    text: 'This PDF link is not valid.',
                    onRetry: null,
                  )
                : PdfViewer.uri(
                    uri,
                    params: PdfViewerParams(
                      backgroundColor: colors.surfaceAlt,
                      loadingBannerBuilder: (context, downloaded, total) =>
                          Center(
                            child: CircularProgressIndicator(
                              // Indeterminate until the server sends a length —
                              // a bar stuck at zero reads as a hang.
                              value: (total != null && total > 0)
                                  ? downloaded / total
                                  : null,
                              color: colors.accentYellow,
                            ),
                          ),
                      errorBannerBuilder:
                          (context, error, stackTrace, documentRef) =>
                              _PdfMessage(
                                text: 'The PDF could not be loaded.',
                                onRetry: () => _openExternally(context),
                              ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A centred failure state with one way forward — opening the file in whatever
/// the device already uses for PDFs, which usually succeeds where the embedded
/// renderer did not.
class _PdfMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _PdfMessage({required this.text, required this.onRetry});

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
            if (onRetry != null) ...[
              const SizedBox(height: 16),
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
