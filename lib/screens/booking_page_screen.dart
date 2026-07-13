import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'payment_screen.dart';

class BookingPageScreen extends StatefulWidget {
  final int tutorId;
  final String tutorName;
  final String tutorImage;
  final String experience;
  final double ieltsScore;
  final DateTime startAt;
  final int durationMinutes;
  final int price;

  const BookingPageScreen({
    super.key,
    required this.tutorId,
    required this.tutorName,
    required this.tutorImage,
    required this.experience,
    required this.ieltsScore,
    required this.startAt,
    required this.durationMinutes,
    required this.price,
  });

  @override
  State<BookingPageScreen> createState() => _BookingPageScreenState();
}

class _BookingPageScreenState extends State<BookingPageScreen> {
  final _goalController = TextEditingController();
  // Multiple goals can be selected; insertion order is preserved so the first
  // selected goal becomes the booking's primary lesson_topic on the server.
  final Set<String> _selectedGoals = {};

  static const List<({String value, String label})> _topics = [
    (value: 'speaking_practice', label: 'Speaking practice'),
    (value: 'speaking_mock', label: 'Speaking mock'),
    (value: 'grammar', label: 'Grammar'),
    (value: 'vocabulary', label: 'Vocabulary'),
    (value: 'ielts_writing', label: 'IELTS Writing'),
    (value: 'ielts_reading', label: 'IELTS Reading'),
  ];

  static const _monthNames = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  String _buildStudentNote() => _goalController.text.trim();

  void _onRequestLesson() {
    if (_selectedGoals.isEmpty) return;
    final d = widget.startAt;
    final endMin = d.hour * 60 + d.minute + widget.durationMinutes;
    final endH = (endMin ~/ 60) % 24;
    final endM = endMin % 60;
    final timeRange =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} - '
        '${endH.toString().padLeft(2, '0')}:${endM.toString().padLeft(2, '0')}';
    final lessonDate = '${d.day} ${_monthNames[d.month - 1]}. ${d.year}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          tutorId: widget.tutorId,
          startAt: widget.startAt,
          durationMinutes: widget.durationMinutes,
          lessonGoals: _selectedGoals.toList(),
          tutorName: widget.tutorName,
          tutorImage: widget.tutorImage,
          experience: widget.experience,
          ieltsScore: widget.ieltsScore.toString(),
          lessonDate: lessonDate,
          timeRange: timeRange,
          duration: '${widget.durationMinutes} min',
          goal: _buildStudentNote(),
          totalAmount: widget.price,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.chevron_left_rounded, size: 30, color: context.colors.textPrimary),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Booking Page',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Icon(Icons.more_vert, size: 24, color: context.colors.textPrimary),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),

                    // Question
                    Text(
                      'What specific skills or topics would you like to improve? (select all that apply)',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Goal chips (multi-select)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _topics.map((topic) {
                        final selected = _selectedGoals.contains(topic.value);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedGoals.remove(topic.value);
                            } else {
                              _selectedGoals.add(topic.value);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? context.colors.brand : context.colors.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: selected ? context.colors.brand : context.colors.border,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              topic.label,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: selected ? Colors.white : context.colors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // Goal text area
                    Container(
                      decoration: BoxDecoration(
                        color: context.colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _goalController,
                            maxLength: 300,
                            maxLines: 6,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 15,
                              color: context.colors.textPrimary,
                              height: 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Describe your goals for this lesson...',
                              hintStyle: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 15,
                                color: context.colors.textTertiary,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
                              counterText: '',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 16, bottom: 10),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                '${_goalController.text.length}/300',
                                style: TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 12,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Request lesson button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onRequestLesson,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Request lesson',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
