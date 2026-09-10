import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../services/affiliate_service.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_notify.dart';
import '../widgets/cached_avatar.dart';
import '../widgets/promo_code_field.dart';

/// The tutor's side of the promo code a student types at Plus checkout.
///
/// The one thing this screen exists to produce is the code itself — dictated
/// in a lesson, pasted into a Telegram bio — so the code is the largest thing
/// here and everything else explains it.
class AffiliateScreen extends StatefulWidget {
  const AffiliateScreen({super.key});

  @override
  State<AffiliateScreen> createState() => _AffiliateScreenState();
}

class _AffiliateScreenState extends State<AffiliateScreen> {
  AffiliateCode? _affiliate;
  AffiliateCommissionsPage _commissions = AffiliateCommissionsPage.empty;
  bool _loading = true;

  /// Set when the code could not be loaded at all — a tutor whose account is
  /// still pending has nothing to promote yet, and saying so is a better
  /// answer than a panel whose every number is a dash.
  String? _loadError;

  final _renameController = TextEditingController();
  bool _renaming = false;
  bool _savingName = false;
  String? _renameError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // The commissions list is not worth failing the screen over: the code is
      // what a tutor came here for.
      final results = await Future.wait([
        AffiliateService.getMyCode(),
        AffiliateService.getCommissions()
            .catchError((_) => AffiliateCommissionsPage.empty),
      ]);
      if (!mounted) return;
      setState(() {
        _affiliate = results[0] as AffiliateCode;
        _commissions = results[1] as AffiliateCommissionsPage;
        _loading = false;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.statusCode == 403
            ? 'Your promo code is created once your tutor account is approved.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your promo code. Pull to try again.';
      });
    }
  }

  Future<void> _copyCode() async {
    final code = _affiliate?.code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    AppNotify.show(context, message: 'Copied', type: NotifyType.success);
  }

  Future<void> _shareCode() async {
    final affiliate = _affiliate;
    if (affiliate == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Use my promo code ${affiliate.code} on Linka and get '
            '${affiliate.discountPercent.round()}% off Linka PLUS: '
            'https://linkaapp.uz',
      ),
    );
  }

  Future<void> _saveName() async {
    final code = AffiliateService.normalizeCode(_renameController.text);
    if (code.length < 4 || _savingName) {
      setState(() => _renameError = 'Use 4–24 letters and digits.');
      return;
    }
    setState(() {
      _savingName = true;
      _renameError = null;
    });
    try {
      final updated = await AffiliateService.renameCode(code);
      if (!mounted) return;
      setState(() {
        _affiliate = updated;
        _renaming = false;
        _renameController.clear();
      });
      AppNotify.show(
        context,
        message: 'Promo code updated',
        type: NotifyType.success,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _renameError = _renameMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _renameError = 'Could not save the code. Try again.');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  /// The refusals worth wording ourselves. Most of them are ones this screen
  /// already hides — they survive because the window can close while the form
  /// is open: a student can buy with the code in that gap.
  String _renameMessage(ApiException e) {
    switch (e.errorCode) {
      case 'invalid_code':
        return 'Use 4–24 letters and digits.';
      case 'code_taken':
        return 'That code is already taken.';
      case 'code_locked':
        return 'The code has been used and can no longer be changed.';
      default:
        return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Symbols.chevron_left_rounded, color: colors.textPrimary, size: 28),
        ),
        title: Text(
          'Promo code',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accentYellow))
          : RefreshIndicator(
              color: colors.textPrimary,
              onRefresh: _load,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: _affiliate == null
                        ? [_Notice(message: _loadError ?? '')]
                        : _panel(context, _affiliate!),
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _panel(BuildContext context, AffiliateCode affiliate) {
    final colors = context.colors;
    return [
      // The terms, in the numbers actually in force for this code — global
      // unless an admin negotiated something else for this tutor, which is why
      // they are read from the server rather than written into the sentence.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.hotel_class_rounded,
              size: 18, fill: 1, color: colors.accentYellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Share your code. Students get '
              '${affiliate.discountPercent.round()}% off Linka PLUS, and you '
              'earn ${affiliate.tutorSharePercent.round()}% of what they pay.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _CodeCard(
        code: affiliate.code,
        onCopy: _copyCode,
        onShare: _shareCode,
      ),
      const SizedBox(height: 12),
      if (affiliate.canRename)
        _renaming
            ? _RenameForm(
                controller: _renameController,
                hint: affiliate.code,
                saving: _savingName,
                error: _renameError,
                onSave: _saveName,
                onCancel: () => setState(() {
                  _renaming = false;
                  _renameError = null;
                  _renameController.clear();
                }),
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _renaming = true),
                  icon: Icon(Symbols.edit_rounded,
                      size: 16, color: colors.accentBlue),
                  label: Text(
                    'Change my code',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.accentBlue,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              )
      else
        // Renaming closes for good on the first purchase, so the reason it is
        // gone is stated rather than the control silently disappearing.
        Text(
          'Your code has been used, so it can no longer be changed.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
          ),
        ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'STUDENTS',
              value: '${affiliate.students}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              label: 'SUBSCRIPTIONS',
              value: '${affiliate.purchases}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              label: 'EARNED',
              value: _formatUzs(affiliate.earnedTotalUzs),
              unit: 'UZS',
              highlight: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        'Your share lands in your earnings balance as soon as the student '
        'pays, and is withdrawn the same way as lesson income.',
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: colors.textTertiary,
        ),
      ),
      const SizedBox(height: 24),
      if (_commissions.entries.isEmpty)
        _Notice(
          message: 'No one has bought PLUS with your code yet.',
          dashed: true,
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'REFERRALS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
        ),
        for (final entry in _commissions.entries) ...[
          _CommissionRow(entry: entry),
          const SizedBox(height: 8),
        ],
      ],
    ];
  }
}

String _formatUzs(int amount) {
  final str = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(str[i]);
  }
  return buffer.toString();
}

// ─── The code itself ────────────────────────────────────────────────────────

/// At the size it is read out loud from.
class _CodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _CodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.brand, Color.lerp(colors.brand, Colors.black, 0.35)!],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR PROMO CODE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _GhostButton(
                icon: Symbols.content_copy_rounded,
                label: 'Copy',
                onTap: onCopy,
              ),
              const SizedBox(width: 8),
              _GhostButton(
                icon: Symbols.ios_share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Students enter this code on the Linka PLUS page before they pay.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GhostButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, weight: 700, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Rename ─────────────────────────────────────────────────────────────────

class _RenameForm extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool saving;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _RenameForm({
    required this.controller,
    required this.hint,
    required this.saving,
    required this.error,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: PromoCodeField(
                controller: controller,
                hintText: hint,
                enabled: !saving,
                autofocus: true,
                onSubmitted: onSave,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: saving ? null : onSave,
                style: TextButton.styleFrom(
                  backgroundColor: colors.brand,
                  foregroundColor: colors.onBrand,
                  disabledBackgroundColor: colors.brand.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: saving ? null : onCancel,
              icon: Icon(Symbols.close_rounded,
                  size: 20, color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          error ?? '4–24 letters and digits. Only until your first sale.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: error == null ? colors.textTertiary : colors.error,
          ),
        ),
      ],
    );
  }
}

// ─── Stats & rows ───────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final bool highlight;

  const _Stat({
    required this.label,
    required this.value,
    this.unit,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: highlight ? colors.success : colors.textPrimary,
                    ),
                  ),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  final AffiliateCommission entry;

  const _CommissionRow({required this.entry});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final date = entry.createdAt?.toLocal();
    final when = date == null
        ? ''
        : '${date.day} ${_months[date.month - 1]}';
    final plan = entry.planTitle ?? '';
    final subtitle = [when, plan].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          CachedAvatar(imageUrl: entry.studentImage, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.studentName.isEmpty ? 'Student' : entry.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${_formatUzs(entry.tutorAmountUzs)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: colors.success,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'of ${_formatUzs(entry.paidAmountUzs)} paid',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String message;
  final bool dashed;

  const _Notice({required this.message, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dashed ? Colors.transparent : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: dashed ? Border.all(color: colors.border) : null,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
