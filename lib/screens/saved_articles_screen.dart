import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'article_detail_screen.dart';

class SavedArticlesScreen extends StatefulWidget {
  const SavedArticlesScreen({super.key});

  @override
  State<SavedArticlesScreen> createState() => _SavedArticlesScreenState();
}

class _SavedArticlesScreenState extends State<SavedArticlesScreen> {
  List<Map<String, dynamic>> _articles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService.get('/student/saved-articles/');
      final list = response['data'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _articles = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _removeBookmark(int articleId) async {
    try {
      await ApiService.delete('/student/saved-articles/$articleId/');
      setState(() => _articles.removeWhere((a) => a['id'] == articleId));
    } catch (e) {
    }
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
          icon: Icon(Symbols.chevron_left_rounded, color: context.colors.textPrimary, size: 28),
        ),
        title: Text(
          'Saved articles',
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
          : _articles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/images/icons/bookmark_outline_16.svg',
                        width: 40,
                        height: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No saved articles yet',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _articles.length,
                  itemBuilder: (context, i) {
                    final article = _articles[i];
                    final title = article['title'] as String? ?? '';
                    final id = article['id'] as int? ?? 0;

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ArticleDetailScreen(articleId: id),
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Image.asset(
                                    'assets/images/article.png',
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    cacheWidth: 280,
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => _removeBookmark(id),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: context.colors.surface,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: SvgPicture.asset(
                                            'assets/images/icons/bookmarked.svg',
                                            width: 14,
                                            height: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
