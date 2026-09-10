import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/api_service.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper>
    with SingleTickerProviderStateMixin {
  bool _isOnline = true;
  bool _checking = false;
  Timer? _timer;
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    ApiService.onNetworkFailure = () => _updateState(false);

    _checkConnectivity();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkConnectivity());
  }

  Future<void> _checkConnectivity() async {
    if (_checking) return;
    _checking = true;
    try {
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      _updateState(true);
    } catch (_) {
      _updateState(false);
    } finally {
      _checking = false;
    }
  }

  void _updateState(bool online) {
    if (online == _isOnline) return;
    setState(() => _isOnline = online);
    if (online) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    ApiService.onNetworkFailure = null;
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        SlideTransition(
          position: _slideAnim,
          child: _NoInternetPage(onRetry: _checkConnectivity),
        ),
      ],
    );
  }
}

class _NoInternetPage extends StatefulWidget {
  final Future<void> Function() onRetry;
  const _NoInternetPage({required this.onRetry});

  @override
  State<_NoInternetPage> createState() => _NoInternetPageState();
}

class _NoInternetPageState extends State<_NoInternetPage>
    with SingleTickerProviderStateMixin {
  bool _retrying = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await widget.onRetry();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF272942),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 1),
              SvgPicture.asset(
                'assets/images/branding/white-logo.svg',
                height: 32,
              ),
              const Spacer(flex: 2),
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Symbols.wifi_off_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                  ),
                  children: [
                    TextSpan(text: 'No Internet\nConnection'),
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: Color(0xFFF5C542)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Please check your Wi-Fi or mobile data\nand try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.55),
                  height: 1.55,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _retrying ? null : _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5C542),
                    disabledBackgroundColor: const Color(0xFFF5C542).withValues(alpha: 0.5),
                    foregroundColor: const Color(0xFF272942),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _retrying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF272942),
                          ),
                        )
                      : const Text(
                          'Try Again',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
