import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_constants.dart';
import '../theme/app_colors.dart';

class PublicOfferScreen extends StatefulWidget {
  const PublicOfferScreen({super.key});

  @override
  State<PublicOfferScreen> createState() => _PublicOfferScreenState();
}

class _PublicOfferScreenState extends State<PublicOfferScreen> {
  bool _loading = true;
  String? _title;
  String? _content;
  String? _lastUpdated;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/public-offer/'),
        headers: {'Content-Type': 'application/json'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _title = data['title'] as String?;
          _lastUpdated = data['last_updated'] as String?;
          _content = (data['content'] as String?)
              ?.replaceAll('\\n', '\n');
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load. Please try again.';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No internet connection.';
        _loading = false;
      });
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
          icon: Icon(Icons.arrow_back_ios, color: context.colors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Public Offer',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: context.colors.textPrimary,
                strokeWidth: 2,
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            _fetch();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.brand,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_title != null) ...[
                        Text(
                          _title!,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (_lastUpdated != null) ...[
                        Text(
                          'Last updated: $_lastUpdated',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_content != null)
                        Text(
                          _content!,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.colors.textSecondary,
                            height: 1.6,
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
