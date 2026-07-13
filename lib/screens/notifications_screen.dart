import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _lessonReminder = true;
  bool _recommendedTutors = true;
  bool _newFeatures = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final data = await ApiService.get('/notifications/preferences/');
      setState(() {
        _lessonReminder = data['notify_lesson_reminder'] ?? true;
        _recommendedTutors = data['notify_recommended_tutors'] ?? true;
        _newFeatures = data['notify_new_features'] ?? true;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _update(String key, bool value) async {
    try {
      await ApiService.patch('/notifications/preferences/', {key: value});
    } catch (_) {
      // Revert on failure
      _loadPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surfaceAlt,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        surfaceTintColor: context.colors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: context.colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToggleRow(
                    label: 'Lesson reminder',
                    value: _lessonReminder,
                    onChanged: (v) {
                      setState(() => _lessonReminder = v);
                      _update('notify_lesson_reminder', v);
                    },
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: context.colors.border),
                  _ToggleRow(
                    label: 'Recommended tutors',
                    value: _recommendedTutors,
                    onChanged: (v) {
                      setState(() => _recommendedTutors = v);
                      _update('notify_recommended_tutors', v);
                    },
                  ),
                  Divider(height: 1, indent: 16, endIndent: 16, color: context.colors.border),
                  _ToggleRow(
                    label: 'New features',
                    value: _newFeatures,
                    onChanged: (v) {
                      setState(() => _newFeatures = v);
                      _update('notify_new_features', v);
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: context.colors.textPrimary,
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: const Color(0xFF3478F6),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
