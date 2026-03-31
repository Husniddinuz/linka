import 'package:flutter/material.dart';

enum PaymentMethod { click, payme, uzum }

class PaymentTopUpScreen extends StatefulWidget {
  const PaymentTopUpScreen({super.key});

  @override
  State<PaymentTopUpScreen> createState() => _PaymentTopUpScreenState();
}

class _PaymentTopUpScreenState extends State<PaymentTopUpScreen> {
  PaymentMethod? _selected;

  void _onTopUp() {
    if (_selected == null) return;
    // TODO: Integrate with actual payment gateway
    // For now, simulate adding 450,000 UZS
    Navigator.pop(context, 450000);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF272942), size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Payment',
          style: TextStyle(
            color: Color(0xFF272942),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF888888),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Click
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.click,
                    onTap: () => setState(() => _selected = PaymentMethod.click),
                    child: Image.asset(
                      'assets/images/branding/click.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Payme
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.payme,
                    onTap: () => setState(() => _selected = PaymentMethod.payme),
                    child: Image.asset(
                      'assets/images/branding/payme.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Uzum Bank
                  _PaymentMethodCard(
                    isSelected: _selected == PaymentMethod.uzum,
                    onTap: () => setState(() => _selected = PaymentMethod.uzum),
                    child: Image.asset(
                      'assets/images/branding/uzum.png',
                      height: 28,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Info text
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F6F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Color(0xFF6C9BD1)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Select from the options to go to the bank app and top up your wallet.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top up button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _selected != null ? _onTopUp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF272942),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Top up',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

// ─── Payment method card ────────────────────────────────────────────────────

class _PaymentMethodCard extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  const _PaymentMethodCard({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFFE8E8E8),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            child,
            const Spacer(),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFFF8C00) : const Color(0xFFCCCCCC),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF8C00),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
