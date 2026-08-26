import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linka/services/affiliate_service.dart';
import 'package:linka/services/plus_service.dart';
import 'package:linka/theme/app_colors.dart';
import 'package:linka/widgets/promo_code_field.dart';

MaterialApp _app(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [AppColors.light]),
    home: Scaffold(body: child),
  );
}

void main() {
  group('promo quote', () {
    test('reads the server\'s decimal strings, not the client\'s arithmetic', () {
      final quote = PromoQuote.fromJson(const {
        'valid': true,
        'promo_code': 'ALIYA472',
        'plan_code': 'yearly',
        'tutor_name': 'Aliya Karimova',
        'list_price_uzs': '240000.00',
        'discount_percent': '15.00',
        'discount_amount_uzs': '36000.00',
        'payable_uzs': '204000.00',
      });

      expect(quote.code, 'ALIYA472');
      expect(quote.tutorName, 'Aliya Karimova');
      // 15%, not the 10% default — the percentage is per code.
      expect(quote.discountPercent, 15);
      expect(quote.discountAmountUzs, 36000);
      expect(quote.listPriceUzs, 240000);
      expect(quote.payableUzs, 204000);
    });

    test('a full-price checkout carries no code', () {
      final result = PlusCheckoutResult.fromJson(const {
        'success': true,
        'plus_until': '2027-08-26T10:00:00Z',
        'balance_uzs': 12000,
        'promo_code': null,
        'discount_amount_uzs': '0.00',
      });

      expect(result.promoCode, isNull);
      expect(result.discountAmountUzs, 0);
      expect(result.plusUntil, isNotNull);
    });
  });

  group('plan pricing', () {
    // The three tariffs as priced on 2026-08-26.
    const monthly = PlusPlan(
        code: 'monthly', title: '1 Month', priceUzs: 99000, durationDays: 30);
    const quarterly = PlusPlan(
        code: 'quarterly',
        title: '3 Months',
        priceUzs: 219000,
        durationDays: 90);
    const yearly = PlusPlan(
        code: 'yearly', title: '1 Year', priceUzs: 799000, durationDays: 365);

    test('a year is twelve months, not 365/30 of them', () {
      expect(monthly.months, 1);
      expect(quarterly.months, 3);
      // The badge reads 33% off twelve months at 99 000, where dividing the
      // 365 days by 30 would claim 34% on the very same two prices.
      expect(yearly.months, 12);
    });

    test('badges are the saving against renewing the monthly plan', () {
      expect(quarterly.savePercentAgainst(monthly), 26);
      expect(yearly.savePercentAgainst(monthly), 33);
    });

    test('the baseline carries no badge, and neither does a bad deal', () {
      expect(monthly.savePercentAgainst(monthly), isNull);
      const overpriced = PlusPlan(
          code: 'quarterly', priceUzs: 400000, durationDays: 90);
      expect(overpriced.savePercentAgainst(monthly), isNull);
      const undated = PlusPlan(code: 'lifetime', priceUzs: 1);
      expect(undated.savePercentAgainst(monthly), isNull);
    });

    test('plans parse from the live /plans/ payload', () {
      final plan = PlusPlan.fromJson(const {
        'code': 'quarterly',
        'title': '3 Months',
        'price_uzs': '219000.00',
        'price_usd': null,
        'usd_available': false,
        'duration_days': 90,
      });
      expect(plan.code, 'quarterly');
      expect(plan.title, '3 Months');
      expect(plan.priceUzs, 219000);
      expect(plan.durationDays, 90);
    });
  });

  group('affiliate code', () {
    test('reads the terms in force for this code and its totals', () {
      final affiliate = AffiliateCode.fromJson(const {
        'code': 'ALIYA472',
        'is_active': true,
        'discount_percent': '15.00',
        'tutor_share_percent': '60.00',
        'can_rename': false,
        'summary': {
          'purchases': 3,
          'students': 2,
          'earned_total_uzs': '367200.00',
        },
        'created_at': '2026-08-01T09:00:00Z',
      });

      expect(affiliate.code, 'ALIYA472');
      expect(affiliate.discountPercent, 15);
      expect(affiliate.tutorSharePercent, 60);
      expect(affiliate.canRename, isFalse);
      expect(affiliate.students, 2);
      expect(affiliate.earnedTotalUzs, 367200);
    });

    test('a commission names the student by first name only', () {
      final page = AffiliateCommissionsPage.fromJson(const {
        'summary': {
          'count': 1,
          'students': 1,
          'paid_total_uzs': '204000.00',
          'discount_total_uzs': '36000.00',
          'tutor_total_uzs': '122400.00',
        },
        'page': 1,
        'limit': 50,
        'data': [
          {
            'id': 7,
            'code_text': 'ALIYA472',
            'plan_title': 'Yearly',
            'student': {'id': 12, 'first_name': 'Dilnoza', 'profile_image': null},
            'list_price_uzs': '240000.00',
            'discount_amount_uzs': '36000.00',
            'paid_amount_uzs': '204000.00',
            'tutor_share_percent': '60.00',
            'tutor_amount_uzs': '122400.00',
            'created_at': '2026-08-20T12:30:00Z',
          }
        ],
      });

      expect(page.count, 1);
      expect(page.tutorTotalUzs, 122400);
      expect(page.entries.single.studentName, 'Dilnoza');
      expect(page.entries.single.tutorAmountUzs, 122400);
      expect(page.entries.single.createdAt, isNotNull);
    });

    test('an empty programme parses to zeroes, not nulls', () {
      final page = AffiliateCommissionsPage.fromJson(const {});
      expect(page.count, 0);
      expect(page.entries, isEmpty);
    });

    test('normalisation matches what the server stores', () {
      expect(AffiliateService.normalizeCode('ali-72'), 'ALI72');
      expect(AffiliateService.normalizeCode(' aliya 472 '), 'ALIYA472');
      expect(AffiliateService.normalizeCode('x' * 40).length, 24);
    });
  });

  testWidgets('the promo field types back the code the server stores',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(PromoCodeField(controller: controller, hintText: 'e.g. ALIYA472')),
    );

    await tester.enterText(find.byType(TextField), 'aliya-472');
    await tester.pump();

    // Punctuation is dropped by the formatter, letters upper-cased: a code
    // dictated in a lesson reaches the API as the code the tutor owns.
    expect(controller.text, 'ALIYA472');
  });
}
