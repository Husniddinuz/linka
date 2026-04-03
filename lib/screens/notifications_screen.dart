import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEEEEE)),
                  _ToggleRow(
                    label: 'Recommended tutors',
                    value: _recommendedTutors,
                    onChanged: (v) {
                      setState(() => _recommendedTutors = v);
                      _update('notify_recommended_tutors', v);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEEEEE)),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black,
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
