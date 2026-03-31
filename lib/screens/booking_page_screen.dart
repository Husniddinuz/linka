import 'package:flutter/material.dart';
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
  final Set<String> _selectedTopics = {};

  static const _topics = [
    'Speaking practice',
    'Speaking mock',
    'Grammar',
    'Vocabulary',
    'IELTS Writing',
    'IELTS Reading',
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

  void _onRequestLesson() {
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
          tutorName: widget.tutorName,
          tutorImage: widget.tutorImage,
          experience: widget.experience,
          ieltsScore: widget.ieltsScore.toString(),
          lessonDate: lessonDate,
          timeRange: timeRange,
          duration: '${widget.durationMinutes} min',
          goal: _goalController.text,
          totalAmount: widget.price,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                    child: const Icon(Icons.chevron_left_rounded, size: 30, color: Color(0xFF272942)),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Booking Page',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF272942),
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: const Icon(Icons.more_vert, size: 24, color: Color(0xFF272942)),
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
                    const Text(
                      'What specific skills or topics would you like to improve?',
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF272942),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Topic chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _topics.map((topic) {
                        final selected = _selectedTopics.contains(topic);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedTopics.remove(topic);
                            } else {
                              _selectedTopics.add(topic);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF272942) : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: selected ? const Color(0xFF272942) : const Color(0xFFDDDDDD),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              topic,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: selected ? Colors.white : const Color(0xFF272942),
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
                        color: const Color(0xFFF5F5F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _goalController,
                            maxLength: 300,
                            maxLines: 6,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 15,
                              color: Color(0xFF272942),
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Describe your goals for this lesson...',
                              hintStyle: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 15,
                                color: Color(0xFFAAAAAA),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                              counterText: '',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 16, bottom: 10),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Text(
                                '${_goalController.text.length}/300',
                                style: const TextStyle(
                                  fontFamily: 'SF Pro',
                                  fontSize: 12,
                                  color: Color(0xFF9E9E9E),
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
                    backgroundColor: const Color(0xFF272942),
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
