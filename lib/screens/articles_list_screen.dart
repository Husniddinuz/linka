import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import 'article_detail_screen.dart';
import 'saved_articles_screen.dart';

class ArticlesListScreen extends StatefulWidget {
  const ArticlesListScreen({super.key});

  @override
  State<ArticlesListScreen> createState() => _ArticlesListScreenState();
}

class _ArticlesListScreenState extends State<ArticlesListScreen> {
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _filtered = [];
  Set<int> _savedArticleIds = {};
  bool _loading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArticles() async {
    try {
      final results = await Future.wait([
        ApiService.getList('/content/articles/'),
        ApiService.get('/student/saved-articles/').catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final list = results[0] as List<dynamic>;
      final savedResponse = results[1] as Map<String, dynamic>;
      final savedList = savedResponse['data'] as List<dynamic>? ?? [];
      _savedArticleIds = savedList
          .map((e) => (e as Map<String, dynamic>)['id'] as int? ?? 0)
          .toSet();
      setState(() {
        _articles = list.cast<Map<String, dynamic>>();
        _filtered = _articles;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleBookmark(int articleId) async {
    try {
      if (_savedArticleIds.contains(articleId)) {
        await ApiService.delete('/student/saved-articles/$articleId/');
        setState(() => _savedArticleIds.remove(articleId));
      } else {
        await ApiService.post('/student/saved-articles/', {'article_id': articleId});
        setState(() => _savedArticleIds.add(articleId));
      }
    } catch (e) {
      dev.log('ARTICLE BOOKMARK ERROR: $e');
    }
  }

  void _onSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _articles;
      } else {
        _filtered = _articles
            .where((a) => (a['title'] as String? ?? '')
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 28),
        ),
        title: const Text(
          'Articles',
          style: TextStyle(
            color: Color(0xFF272942),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SavedArticlesScreen()),
            ),
            icon: SvgPicture.asset(
              'assets/images/icons/bookmark_outline_16.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(Color(0xFF272942), BlendMode.srcIn),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5C542)))
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearch,
                      decoration: const InputDecoration(
                        hintText: 'Keyword search',
                        hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: Color(0xFFAAAAAA), size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 14, color: Color(0xFF272942)),
                    ),
                  ),
                ),
                // Grid
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No articles found',
                            style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
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
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final article = _filtered[i];
                            final title = article['title'] as String? ?? '';
                            final id = article['id'] as int;
                            final isSaved = _savedArticleIds.contains(id);

                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ArticleDetailScreen(articleId: id),
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF6F6F6),
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
                                              onTap: () => _toggleBookmark(id),
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: SvgPicture.asset(
                                                    isSaved
                                                        ? 'assets/images/icons/bookmarked.svg'
                                                        : 'assets/images/icons/bookmark_outline_16.svg',
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
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF272942),
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
                ),
              ],
            ),
    );
  }
}
