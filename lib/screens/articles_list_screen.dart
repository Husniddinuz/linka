import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../widgets/new_badge.dart';
import 'article_detail_screen.dart';
import 'saved_articles_screen.dart';

class ArticlesListScreen extends StatefulWidget {
  const ArticlesListScreen({super.key});

  @override
  State<ArticlesListScreen> createState() => _ArticlesListScreenState();
}

class _ArticlesListScreenState extends State<ArticlesListScreen> {
  static const _accents = [
    Color(0xFF4776E6),
    Color(0xFF11998E),
    Color(0xFFEB3349),
    Color(0xFFF7971E),
    Color(0xFF8E54E9),
    Color(0xFF1D976C),
  ];

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
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isTablet = MediaQuery.of(context).size.width >= 600;
                            final cols = isTablet ? 3 : 2;
                            const spacing = 12.0;
                            const hPad = 16.0;
                            final cardWidth = (constraints.maxWidth - hPad * 2 - spacing * (cols - 1)) / cols;
                            final imageHeight = cardWidth * (110 / 140);
                            const textSection = 52.0;
                            final aspectRatio = cardWidth / (imageHeight + textSection);

                            return GridView.builder(
                              padding: const EdgeInsets.all(hPad),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                childAspectRatio: aspectRatio,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) {
                                final article = _filtered[i];
                                final title = article['title'] as String? ?? '';
                                final id = article['id'] as int;
                                final isNew = article['is_new'] as bool? ?? false;
                                final isSaved = _savedArticleIds.contains(id);
                                final accent = _accents[i % _accents.length];

                                return GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ArticleDetailScreen(articleId: id),
                                    ),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFEEEEEE)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withValues(alpha: 0.10),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.hardEdge,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 140 / 110,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            clipBehavior: Clip.hardEdge,
                                            children: [
                                              Container(color: accent),
                                              Positioned(
                                                top: -28,
                                                right: -28,
                                                child: Container(
                                                  width: 100,
                                                  height: 100,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white.withValues(alpha: 0.10),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: -18,
                                                left: -18,
                                                child: Container(
                                                  width: 72,
                                                  height: 72,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white.withValues(alpha: 0.08),
                                                  ),
                                                ),
                                              ),
                                              Center(
                                                child: SvgPicture.asset(
                                                  'assets/images/branding/white-logo.svg',
                                                  height: 28,
                                                  colorFilter: ColorFilter.mode(
                                                    Colors.white.withValues(alpha: 0.90),
                                                    BlendMode.srcIn,
                                                  ),
                                                ),
                                              ),
                                              if (isNew)
                                                const Positioned(
                                                  top: 10,
                                                  left: 10,
                                                  child: NewBadge(onColored: true),
                                                ),
                                              Positioned(
                                                top: 10,
                                                right: 10,
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: () => _toggleBookmark(id),
                                                  child: Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withValues(alpha: 0.20),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Center(
                                                      child: SvgPicture.asset(
                                                        isSaved
                                                            ? 'assets/images/icons/bookmarked.svg'
                                                            : 'assets/images/icons/bookmark_outline_16.svg',
                                                        width: 14,
                                                        height: 14,
                                                        colorFilter: const ColorFilter.mode(
                                                          Colors.white,
                                                          BlendMode.srcIn,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 10,
                                                right: 12,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.20),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: const Text(
                                                    'ARTICLE',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w700,
                                                      color: Colors.white,
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                            child: Text(
                                              title,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF272942),
                                                height: 1.35,
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        Container(height: 3, color: accent),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
