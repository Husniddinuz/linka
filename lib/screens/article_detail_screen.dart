import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'article_pdf_screen.dart';

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
                  // Below the body, not above it: the PDF supplements the
                  // article rather than replacing it, and a card offered
                  // first is a card taken instead of reading the page.
                  if (_pdfUrl != null) ...[
                    const SizedBox(height: 28),
                    _PdfCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArticlePdfScreen(
                            url: _pdfUrl!,
                            title: _title,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

/// The tap target that opens the attachment. A row rather than a bare link so
/// that it reads as a second thing to do with the article, and so the icon
/// says "PDF" before the label is read.
class _PdfCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PdfCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.picture_as_pdf_outlined,
                color: colors.accentBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attached PDF',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'The full handout, exactly as it is printed.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.textTertiary, size: 22),
          ],
        ),
      ),
    );
  }
}
