import 'package:flutter/material.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import 'ielts_id_upload_screen.dart';

/// Dev/debug shortcut: lists the signed-in candidate's existing
/// applications and jumps straight to [IeltsIdUploadScreen] for one of
/// them, re-fetching the already-saved profile fresh from the server
/// instead of re-running the whole registration wizard. Exists purely to
/// speed up iterating on the ID-upload step without re-entering every
/// field each time.
class IeltsResumeUploadScreen extends StatefulWidget {
  const IeltsResumeUploadScreen({super.key});

  @override
  State<IeltsResumeUploadScreen> createState() => _IeltsResumeUploadScreenState();
}

class _IeltsResumeUploadScreenState extends State<IeltsResumeUploadScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _applications = [];
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await IeltsRegistrationService.getApplicationsDashboard();
      final past = (dashboard['pastTests'] as List? ?? []).cast<Map<String, dynamic>>();
      final upcoming = (dashboard['upcomingTests'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _applications = [...upcoming, ...past];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> app) async {
    setState(() => _opening = true);
    try {
      final applicationId = app['applicationId'] as String;
      final results = await Future.wait([
        IeltsRegistrationService.getApplication(applicationId),
        IeltsRegistrationService.getUserProfile(),
      ]);
      final application = results[0];
      final profile = results[1];
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsIdUploadScreen(
            application: application,
            profile: {...profile, 'id': profile['userProfileId']},
            mobileNumber: profile['mobileNumber'] as String? ?? '',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open: $e')));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Resume Application (dev)'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: MockTestColors.navy))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red)),
                        const SizedBox(height: 16),
                        MtPrimaryButton(label: 'Retry', onPressed: _load),
                      ],
                    ),
                  ),
                )
              : _applications.isEmpty
                  ? const Center(
                      child: Text('No applications on this account yet.', style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _applications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final app = _applications[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _opening ? null : () => _open(app),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: mtSoftCard(context, radius: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  app['productName']?.toString() ?? 'IELTS application',
                                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 14.5, fontWeight: FontWeight.w700, color: MockTestColors.navy),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${app['testLocationName'] ?? ''} · ${app['status'] ?? ''}',
                                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, color: MockTestColors.grey),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'applicationId: ${app['applicationId']}',
                                  style: const TextStyle(fontFamily: 'SF Pro', fontSize: 11, color: MockTestColors.greyLight),
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
