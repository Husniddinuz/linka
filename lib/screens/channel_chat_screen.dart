import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:image_picker/image_picker.dart';
import '../services/token_service.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../services/podcast_playback_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../widgets/skeleton.dart';
import 'chats_screen.dart';
import 'tutor_profile_screen.dart';

// ─── Reply-to model ────────────────────────────────────────────────────────────

class _ReplyTo {
  final String id;
  final String? senderName;
  final String? text;
  final bool isVoice;
  final bool isImage;
  final bool isDeleted;

  const _ReplyTo({
    required this.id,
    this.senderName,
    this.text,
    required this.isVoice,
    this.isImage = false,
    required this.isDeleted,
  });

  factory _ReplyTo.fromJson(Map<String, dynamic> json) => _ReplyTo(
        id: json['id']?.toString() ?? '',
        senderName: json['sender_name'] as String?,
        text: json['text'] as String?,
        isVoice: json['is_voice'] as bool? ?? false,
        isImage: json['is_image'] as bool? ?? false,
        isDeleted: json['is_deleted'] as bool? ?? false,
      );
}

// ─── Quiz models ───────────────────────────────────────────────────────────────

class _QuizOption {
  final int id;
  final String text;
  final bool? isCorrect;
  final int answerCount;

  const _QuizOption({
    required this.id,
    required this.text,
    this.isCorrect,
    required this.answerCount,
  });

  factory _QuizOption.fromJson(Map<String, dynamic> json) => _QuizOption(
        id: (json['id'] as num).toInt(),
        text: json['text']?.toString() ?? '',
        isCorrect: json['is_correct'] as bool?,
        answerCount: (json['answer_count'] as num?)?.toInt() ?? 0,
      );

  _QuizOption copyWith({bool? isCorrect, int? answerCount}) => _QuizOption(
        id: id,
        text: text,
        isCorrect: isCorrect ?? this.isCorrect,
        answerCount: answerCount ?? this.answerCount,
      );
}

class _QuizData {
  final int id;
  final String title;
  final bool hasAnswered;
  final int? myAnswerId;
  final List<_QuizOption> options;

  const _QuizData({
    required this.id,
    required this.title,
    required this.hasAnswered,
    this.myAnswerId,
    required this.options,
  });

  factory _QuizData.fromJson(Map<String, dynamic> json) => _QuizData(
        id: (json['id'] as num).toInt(),
        title: json['title']?.toString() ?? '',
        hasAnswered: json['has_answered'] as bool? ?? false,
        myAnswerId: (json['my_answer_id'] as num?)?.toInt(),
        options: (json['options'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(_QuizOption.fromJson)
            .toList(),
      );

  _QuizData copyWith({
    bool? hasAnswered,
    int? myAnswerId,
    List<_QuizOption>? options,
  }) =>
      _QuizData(
        id: id,
        title: title,
        hasAnswered: hasAnswered ?? this.hasAnswered,
        myAnswerId: myAnswerId ?? this.myAnswerId,
        options: options ?? this.options,
      );

  int get totalVotes => options.fold(0, (s, o) => s + o.answerCount);
}

// ─── Message model ─────────────────────────────────────────────────────────────

class _Message {
  final String id;
  final int senderId;
  final String senderName;
  final String senderInitials;
  final String? senderAvatar;
  final Color senderColor;
  final String? text;
  final bool isImage;
  final String? imageUrl;
  final bool isVoice;
  final int voiceDuration;
  final String? voiceUrl;
  final bool isQuiz;
  final _QuizData? quiz;
  final DateTime sentAt;
  final bool isMine;
  final bool isTutor;
  final int? tutorId;
  final double? tutorIeltsScore;
  final bool isDeleted;
  final _ReplyTo? replyTo;

  static const _palette = [
    Color(0xFF5B7FD4),
    Color(0xFF11998E),
    Color(0xFFEB3349),
    Color(0xFF8E54E9),
    Color(0xFF4776E6),
    Color(0xFF26A69A),
    Color(0xFFF5C542),
    Color(0xFF9575CD),
    Color(0xFFEF5350),
    Color(0xFFFFB300),
  ];

  const _Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderInitials,
    this.senderAvatar,
    required this.senderColor,
    this.text,
    this.isImage = false,
    this.imageUrl,
    this.isVoice = false,
    this.voiceDuration = 0,
    this.voiceUrl,
    this.isQuiz = false,
    this.quiz,
    required this.sentAt,
    this.isMine = false,
    this.isTutor = false,
    this.tutorId,
    this.tutorIeltsScore,
    this.isDeleted = false,
    this.replyTo,
  });

  factory _Message.fromJson(Map<String, dynamic> json) {
    final senderId = (json['sender_id'] as num?)?.toInt() ?? 0;
    final senderName = json['sender_name']?.toString() ?? '';
    final rawInitials = json['sender_initials']?.toString() ?? '';
    final isQuiz = json['is_quiz'] as bool? ?? false;
    return _Message(
      id: json['id']?.toString() ?? '',
      senderId: senderId,
      senderName: senderName,
      senderInitials: rawInitials.isNotEmpty ? rawInitials : _initialsFrom(senderName),
      senderAvatar: ChatService.absoluteUrl(json['sender_avatar'] as String?),
      senderColor: _palette[senderId % _palette.length],
      text: json['text'] as String?,
      isImage: json['is_image'] as bool? ?? false,
      imageUrl: ChatService.absoluteUrl(json['image_url'] as String?),
      isVoice: json['is_voice'] as bool? ?? false,
      voiceDuration: (json['voice_duration'] as num?)?.toInt() ?? 0,
      voiceUrl: ChatService.absoluteUrl(json['voice_url'] as String?),
      isQuiz: isQuiz,
      quiz: isQuiz && json['quiz'] is Map<String, dynamic>
          ? _QuizData.fromJson(json['quiz'] as Map<String, dynamic>)
          : null,
      sentAt: _parseDate(json['sent_at']?.toString()),
      isMine: json['is_mine'] as bool? ?? false,
      isTutor: json['is_tutor'] as bool? ?? false,
      tutorId: (json['tutor_id'] as num?)?.toInt(),
      tutorIeltsScore: (json['tutor_ielts_score'] as num?)?.toDouble(),
      isDeleted: json['is_deleted'] as bool? ?? false,
      replyTo: json['reply_to'] is Map<String, dynamic>
          ? _ReplyTo.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
    );
  }

  _Message copyWith({bool? isDeleted, _QuizData? quiz}) => _Message(
        id: id,
        senderId: senderId,
        senderName: senderName,
        senderInitials: senderInitials,
        senderAvatar: senderAvatar,
        senderColor: senderColor,
        text: text,
        isImage: isImage,
        imageUrl: imageUrl,
        isVoice: isVoice,
        voiceDuration: voiceDuration,
        voiceUrl: voiceUrl,
        isQuiz: isQuiz,
        quiz: quiz ?? this.quiz,
        sentAt: sentAt,
        isMine: isMine,
        isTutor: isTutor,
        tutorId: tutorId,
        tutorIeltsScore: tutorIeltsScore,
        isDeleted: isDeleted ?? this.isDeleted,
        replyTo: replyTo,
      );

  static String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  static DateTime _parseDate(String? raw) {
    if (raw == null) return DateTime.now();
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }
}

// ─── Screen ────────────────────────────────────────────────────────────────────

class ChannelChatScreen extends StatefulWidget {
  final ChatChannel channel;
  // When the screen is opened from a push notification, pass the message_id
  // to scroll to that message after the initial load.
  final String? initialScrollToId;
  const ChannelChatScreen({super.key, required this.channel, this.initialScrollToId});

  @override
  State<ChannelChatScreen> createState() => _ChannelChatScreenState();
}

class _ChannelChatScreenState extends State<ChannelChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showScrollToBottomFab = false;

  List<_Message> _messages = [];
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _currentUserId;
  String? _pendingLocalId;

  _Message? _replyingTo;
  _Message? _pinnedMessage;

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final _recorder = AudioRecorder();

  String? _playingId;
  int? _playTotalSeconds;
  // messageId → fraction downloaded (0.0-1.0), absent once not downloading.
  final Map<String, double> _downloadProgress = {};
  // just_audio_background allows only one live AudioPlayer app-wide, so
  // playback of *received* voice messages shares PodcastPlaybackService's
  // instance instead of constructing its own (which would throw "single
  // player instance").
  AudioPlayer get _player => PodcastPlaybackService.instance.player;
  StreamSubscription? _playerStateSub;

  // Recording preview (before send) uses its own independent audioplayers
  // instance rather than the just_audio_background-managed shared player
  // above — it's a short-lived local-only playback with no need for
  // lock-screen controls, and reusing the shared instance here caused a
  // string of state-sync races (stale replayed "completed" events, queue
  // index confusion with podcasts, activation races on rapid re-taps).
  String? _recordedPath;
  int _recordedDuration = 0;
  ap.AudioPlayer? _previewPlayer;
  StreamSubscription<void>? _previewCompleteSub;
  bool _previewPlaying = false;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;

  // Posting permissions
  bool _currentUserIsTutor = false;

  // Blocked users
  final Set<int> _blockedUserIds = {};

  // Quiz submission state
  final Set<int> _quizSubmitting = {};
  final Map<int, int> _quizPendingOption = {};

  // Reply navigation state
  String? _highlightedId;
  final Set<String> _pendingReplyIds = {};
  bool _showReplyBadge = false;
  final Map<String, GlobalKey> _messageKeys = {};

  // Typing OUT (client → server)
  bool _isTypingOut = false;
  Timer? _typingRepeatTimer;

  // Typing IN (server → client): userId → display first name
  final Map<int, String> _typingUsers = {};
  final Map<int, Timer> _typingClearTimers = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCurrentUserId().then((_) => _connectWs());
    _loadCurrentUserIsTutor();
    _loadBlockedUsers();
    _loadMessages();
    _scrollController.addListener(_onScroll);
    _textController.addListener(_onTextChanged);
  }

  @override
  void deactivate() {
    WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).viewInsets.bottom > 0) {
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTypingOut();
    _typingRepeatTimer?.cancel();
    for (final t in _typingClearTimers.values) {
      t.cancel();
    }
    _textController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _wsChannel?.sink.close();
    _playerStateSub?.cancel();
    // Never dispose the shared player — it's PodcastPlaybackService's
    // app-lifetime instance. Just pause it if this screen was using it.
    if (_playingId != null) {
      _player.pause();
    }
    _previewCompleteSub?.cancel();
    _previewPlayer?.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ─── Current user ──────────────────────────────────────────────────────────

  Future<void> _loadCurrentUserId() async {
    final token = await TokenService.getAccessToken();
    if (token == null) return;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      _currentUserId = payload['user_id']?.toString();
    } catch (_) {}
  }

  Future<void> _loadCurrentUserIsTutor() async {
    final fromCache = UserService.current?.isTeacher
        ?? await UserService.getCachedIsTeacher()
        ?? false;
    if (mounted) setState(() => _currentUserIsTutor = fromCache);
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final raw = await ChatService.fetchBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUserIds.addAll(
            raw.map((u) => (u['user_id'] as num).toInt()),
          );
        });
      }
    } catch (_) {}
  }

  // ─── Report ────────────────────────────────────────────────────────────────

  void _showReportSheet(_Message msg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReportSheet(
        onSubmit: (reason, comment) => _submitReport(msg, reason, comment),
      ),
    );
  }

  Future<void> _submitReport(_Message msg, String reason, String comment) async {
    try {
      await ChatService.reportMessage(
        messageId: int.parse(msg.id),
        reason: reason,
        comment: comment,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message reported. Thank you.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send report. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Block ─────────────────────────────────────────────────────────────────

  Future<void> _confirmBlock(_Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Block ${msg.senderName}?',
          style: const TextStyle(
            fontFamily: 'SF Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: const Text(
          "You won't see their messages in any channel. You can unblock them later in Settings → Blocked users.",
          style: TextStyle(fontFamily: 'SF Pro'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Block',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _blockUser(msg);
  }

  Future<void> _blockUser(_Message msg) async {
    try {
      await ChatService.blockUser(userId: msg.senderId);
      if (!mounted) return;
      setState(() {
        _blockedUserIds.add(msg.senderId);
        _messages.removeWhere((m) => m.senderId == msg.senderId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${msg.senderName} blocked.'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _unblockUser(msg.senderId),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _unblockUser(int userId) async {
    try {
      await ChatService.unblockUser(userId: userId);
      if (!mounted) return;
      setState(() => _blockedUserIds.remove(userId));
    } catch (_) {}
  }

  // ─── Quiz ──────────────────────────────────────────────────────────────────

  Future<void> _submitQuizAnswer(
      String messageId, int quizId, int optionId) async {
    if (_quizSubmitting.contains(quizId)) return;
    setState(() {
      _quizSubmitting.add(quizId);
      _quizPendingOption[quizId] = optionId;
    });
    try {
      final result = await ChatService.submitQuizAnswer(
          widget.channel.id, quizId, optionId);
      if (!mounted) return;
      setState(() {
        _quizSubmitting.remove(quizId);
        _quizPendingOption.remove(quizId);
        _messages = _messages.map((m) {
          if (m.quiz?.id != quizId) return m;
          final rawOpts =
              (result['options'] as List? ?? []).cast<Map<String, dynamic>>();
          final newOptions = m.quiz!.options.map((opt) {
            final ro = rawOpts.firstWhere(
              (o) => (o['id'] as num?)?.toInt() == opt.id,
              orElse: () => <String, dynamic>{},
            );
            if (ro.isEmpty) return opt;
            return opt.copyWith(
              isCorrect: ro['is_correct'] as bool?,
              answerCount:
                  (ro['answer_count'] as num?)?.toInt() ?? opt.answerCount,
            );
          }).toList();
          return m.copyWith(
            quiz: m.quiz!.copyWith(
              hasAnswered: true,
              myAnswerId: (result['my_answer_id'] as num?)?.toInt(),
              options: newOptions,
            ),
          );
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quizSubmitting.remove(quizId);
        _quizPendingOption.remove(quizId);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(e is ApiException ? e.message : 'Failed to submit answer'),
        backgroundColor: context.colors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openCreateQuizSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CreateQuizSheet(slug: widget.channel.id),
    );
  }

  Future<void> _pickAndSendAudioFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) {
      return;
    }
    final path = result.files.first.path!;
    if (!mounted) return;

    final replyingTo = _replyingTo;
    setState(() => _replyingTo = null);

    // Probe the file's duration for display purposes, same approach used
    // for voice-message playback (some codecs report duration async).
    int duration = 0;
    final probePlayer = AudioPlayer();
    try {
      final dur = await probePlayer.setAudioSource(AudioSource.uri(
        Uri.file(path),
        tag: const MediaItem(id: 'audio_probe', title: 'Audio file'),
      ));
      duration = (dur ?? probePlayer.duration)?.inSeconds ??
          await probePlayer.durationStream
              .firstWhere((d) => d != null)
              .timeout(const Duration(seconds: 2), onTimeout: () => null)
              .then((d) => d?.inSeconds ?? 0);
    } catch (_) {
    } finally {
      await probePlayer.dispose();
    }

    _addLocalMessage(
      isVoice: true,
      voiceDuration: duration,
      replyTo: replyingTo != null
          ? _ReplyTo(
              id: replyingTo.id,
              senderName: replyingTo.senderName,
              text: replyingTo.text,
              isVoice: replyingTo.isVoice,
              isDeleted: replyingTo.isDeleted,
            )
          : null,
    );
    ChatService.uploadVoiceMessage(
      widget.channel.id,
      File(path),
      duration,
      replyToId: replyingTo?.id,
    ).catchError((_) {});
  }

  // ─── Reply navigation ──────────────────────────────────────────────────────

  void _highlight(String messageId) {
    setState(() => _highlightedId = messageId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  Future<void> _scrollToMessageById(String messageId) async {
    if (!_scrollController.hasClients) return;

    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
      return;
    }

    // Item not in viewport — estimate position by list index fraction
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final fraction =
        _messages.isNotEmpty ? (idx + 1) / (_messages.length + 1) : 0.0;
    await _scrollController.animateTo(
      (fraction * maxExtent).clamp(0.0, maxExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    await WidgetsBinding.instance.endOfFrame;
    final retryKey = _messageKeys[messageId];
    if (retryKey?.currentContext != null) {
      await Scrollable.ensureVisible(
        retryKey!.currentContext!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: 0.3,
      );
    }
  }

  Future<void> _scrollToOriginal(String replyToId) async {
    var idx = _messages.indexWhere((m) => m.id == replyToId);
    while (idx == -1 && _hasMore) {
      await _loadOlderMessages();
      await WidgetsBinding.instance.endOfFrame;
      idx = _messages.indexWhere((m) => m.id == replyToId);
    }

    if (idx == -1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Original message not available'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    await _scrollToMessageById(replyToId);
    _highlight(replyToId);
  }

  void _onReplyBadgeTap() {
    if (_pendingReplyIds.isEmpty) return;
    final targetId = _pendingReplyIds.last;
    setState(() {
      _pendingReplyIds.clear();
      _showReplyBadge = false;
    });
    _scrollToMessageById(targetId).then((_) => _highlight(targetId));
  }

  // ─── Typing OUT ────────────────────────────────────────────────────────────

  void _onTextChanged() {
    final hasText = _textController.text.isNotEmpty;
    if (hasText && !_isTypingOut) {
      _isTypingOut = true;
      _wsSend({'type': 'typing', 'is_typing': true});
      _typingRepeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_isTypingOut) _wsSend({'type': 'typing', 'is_typing': true});
      });
    } else if (!hasText && _isTypingOut) {
      _stopTypingOut();
    }
  }

  void _stopTypingOut() {
    if (!_isTypingOut) return;
    _isTypingOut = false;
    _typingRepeatTimer?.cancel();
    _typingRepeatTimer = null;
    _wsSend({'type': 'typing', 'is_typing': false});
  }

  // ─── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadMessages() async {
    setState(() => _loadingInitial = true);
    try {
      final data = await ChatService.fetchMessages(widget.channel.id);
      final msgs = (data['results'] as List)
          .cast<Map<String, dynamic>>()
          .map(_Message.fromJson)
          .where((m) => !m.isDeleted)
          .toList();
      final pinnedJson = data['pinned_message'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _messages = msgs;
          _hasMore = data['has_more'] as bool? ?? false;
          _loadingInitial = false;
          _pinnedMessage = pinnedJson != null ? _Message.fromJson(pinnedJson) : null;
        });
        if (widget.initialScrollToId != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _scrollToOriginal(widget.initialScrollToId!),
          );
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final oldestId = _messages.first.id;
    final prevOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final prevMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    try {
      final data = await ChatService.fetchMessages(
        widget.channel.id,
        before: oldestId,
      );
      final older = (data['results'] as List)
          .cast<Map<String, dynamic>>()
          .map(_Message.fromJson)
          .toList();
      if (mounted) {
        setState(() {
          _messages = [...older, ..._messages];
          _hasMore = data['has_more'] as bool? ?? false;
          _loadingMore = false;
        });
        // Preserve scroll position after prepending older messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final added =
                _scrollController.position.maxScrollExtent - prevMaxExtent;
            _scrollController.jumpTo(prevOffset + added);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ─── WebSocket ─────────────────────────────────────────────────────────────

  Future<void> _connectWs() async {
    try {
      _wsChannel = await ChatService.connectWebSocket(widget.channel.id);
      // web_socket_channel 3.x: await ready to surface connection errors
      // (e.g. "not upgraded to websocket") inside this try-catch.
      await _wsChannel!.ready;
      _wsSub = _wsChannel!.stream.listen(
        (data) {
          try {
            final json =
                jsonDecode(data as String) as Map<String, dynamic>;
            if (json['type'] == 'new_message') {
              final msgData = json['message'] as Map<String, dynamic>;
              final senderIdInt = (msgData['sender_id'] as num?)?.toInt();
              final senderId = senderIdInt?.toString();
              final isMine = _currentUserId != null &&
                  senderId == _currentUserId;
              if (!isMine &&
                  senderIdInt != null &&
                  _blockedUserIds.contains(senderIdInt)) {
                return;
              }
              final msg = _Message.fromJson({
                ...msgData,
                'is_mine': isMine,
              });
              if (mounted) {
                final wasNearBottom = _isNearBottom;
                setState(() {
                  if (isMine && _pendingLocalId != null) {
                    // Replace optimistic local message with real server copy
                    _messages = [
                      ..._messages.where((m) => m.id != _pendingLocalId),
                      msg,
                    ];
                    _pendingLocalId = null;
                  } else {
                    _messages = [..._messages, msg];
                  }
                });
                // Show @ badge when someone replies to the current user's message
                if (!isMine && msg.replyTo != null) {
                  final replyToId = msg.replyTo!.id;
                  final isReplyToMine =
                      _messages.any((m) => m.id == replyToId && m.isMine);
                  if (isReplyToMine) {
                    setState(() {
                      _pendingReplyIds.add(msg.id);
                      _showReplyBadge = true;
                    });
                  }
                }
                // Only auto-scroll if the user was already at the bottom;
                // otherwise keep their scroll position and reveal the FAB.
                if (wasNearBottom || isMine) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _scrollToBottom());
                } else if (!_showScrollToBottomFab) {
                  setState(() => _showScrollToBottomFab = true);
                }
              }
            } else if (json['type'] == 'message_deleted') {
              final messageId = json['message_id']?.toString();
              if (messageId != null && mounted) {
                setState(() {
                  _messages = _messages.where((m) => m.id != messageId).toList();
                });
              }
            } else if (json['type'] == 'message_pinned') {
              final msgData = json['message'] as Map<String, dynamic>?;
              if (msgData != null && mounted) {
                final senderId = (msgData['sender_id'] as num?)?.toInt().toString();
                setState(() {
                  _pinnedMessage = _Message.fromJson({
                    ...msgData,
                    'is_mine': _currentUserId != null && senderId == _currentUserId,
                  });
                });
              }
            } else if (json['type'] == 'message_unpinned') {
              if (mounted) setState(() => _pinnedMessage = null);
            } else if (json['type'] == 'typing' && mounted) {
              final userId = (json['user_id'] as num?)?.toInt();
              final userName = json['user_name'] as String?;
              final isTyping = json['is_typing'] as bool? ?? false;
              final currentId = int.tryParse(_currentUserId ?? '');
              if (userId != null && userId != currentId) {
                _typingClearTimers[userId]?.cancel();
                if (isTyping && userName != null) {
                  final firstName = userName.split(' ').first;
                  setState(() => _typingUsers[userId] = firstName);
                  _typingClearTimers[userId] = Timer(const Duration(seconds: 6), () {
                    if (mounted) {
                      setState(() {
                        _typingUsers.remove(userId);
                        _typingClearTimers.remove(userId);
                      });
                    }
                  });
                } else {
                  setState(() {
                    _typingUsers.remove(userId);
                    _typingClearTimers.remove(userId);
                  });
                }
              }
            } else if (json['type'] == 'quiz_updated') {
              final messageId = json['message_id']?.toString();
              final updatedOpts = (json['options'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              if (messageId != null && mounted) {
                setState(() {
                  _messages = _messages.map((m) {
                    if (m.id != messageId || m.quiz == null) return m;
                    final newOptions = m.quiz!.options.map((opt) {
                      final upd = updatedOpts.firstWhere(
                        (o) => (o['id'] as num?)?.toInt() == opt.id,
                        orElse: () => <String, dynamic>{},
                      );
                      if (upd.isEmpty) return opt;
                      return opt.copyWith(
                        answerCount: (upd['answer_count'] as num?)?.toInt() ??
                            opt.answerCount,
                      );
                    }).toList();
                    return m.copyWith(
                        quiz: m.quiz!.copyWith(options: newOptions));
                  }).toList();
                });
              }
            } else if (json['type'] == 'error' && mounted) {
              final detail = json['detail'] as String?;
              if (detail != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(detail),
                    backgroundColor: context.colors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          } catch (_) {}
        },
        onError: (_) {
          if (mounted) setState(() => _wsChannel = null);
        },
        cancelOnError: false,
      );
      _wsSend({'type': 'mark_read'});
    } catch (_) {
      _wsChannel = null;
      await ChatService.markRead(widget.channel.id);
    }
  }

  void _addLocalMessage({
    String? text,
    bool isVoice = false,
    int voiceDuration = 0,
    bool isImage = false,
    _ReplyTo? replyTo,
  }) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final msg = _Message(
      id: id,
      senderId: 0,
      senderName: '',
      senderInitials: 'ME',
      senderColor: const Color(0xFF272942),
      text: text,
      isVoice: isVoice,
      voiceDuration: voiceDuration,
      isImage: isImage,
      sentAt: DateTime.now(),
      isMine: true,
      replyTo: replyTo,
    );
    _pendingLocalId = id;
    setState(() => _messages = [..._messages, msg]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _wsSend(Map<String, dynamic> payload) {
    try {
      _wsChannel?.sink.add(jsonEncode(payload));
    } catch (_) {
      _wsChannel = null;
    }
  }

  // ─── Scroll ────────────────────────────────────────────────────────────────

  static const _kNearBottomThreshold = 120.0;

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <
        _kNearBottomThreshold;
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels < 120) {
      _loadOlderMessages();
    }
    final showFab = !_isNearBottom;
    if (showFab != _showScrollToBottomFab) {
      setState(() => _showScrollToBottomFab = showFab);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
    if (_showScrollToBottomFab) {
      setState(() => _showScrollToBottomFab = false);
    }
  }

  void _scrollToBottomAnimated() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ─── Send text ─────────────────────────────────────────────────────────────

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _stopTypingOut();
    _textController.clear();

    final replyingTo = _replyingTo;
    setState(() => _replyingTo = null);

    final replyToId = replyingTo?.id;
    final replyToArg = replyingTo != null
        ? _ReplyTo(
            id: replyingTo.id,
            senderName: replyingTo.senderName,
            text: replyingTo.text,
            isVoice: replyingTo.isVoice,
            isDeleted: replyingTo.isDeleted,
          )
        : null;

    // Always add an optimistic local bubble immediately — relying solely on
    // the WS echo left the send looking like a no-op whenever that socket
    // was dead/reconnecting (it has no onDone/reconnect handling, so
    // _wsChannel can be non-null but silently unable to deliver).
    _addLocalMessage(text: text, replyTo: replyToArg);

    if (_wsChannel != null) {
      // WS delivers new_message back to all clients including sender, which
      // reconciles the optimistic bubble above via _pendingLocalId.
      _wsSend({
        'type': 'send_message',
        'text': text,
        if (replyToId != null) 'reply_to_id': int.tryParse(replyToId) ?? replyToId,
      });
    } else {
      ChatService.sendTextMessageRest(
        widget.channel.id,
        text,
        replyToId: replyToId,
      ).catchError((_) {});
    }
  }

  // ─── Send image ────────────────────────────────────────────────────────────

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final replyingTo = _replyingTo;
    setState(() => _replyingTo = null);

    // Optimistic local placeholder bubble
    _addLocalMessage(isImage: true, replyTo: replyingTo != null
        ? _ReplyTo(
            id: replyingTo.id,
            senderName: replyingTo.senderName,
            text: replyingTo.text,
            isVoice: replyingTo.isVoice,
            isImage: replyingTo.isImage,
            isDeleted: replyingTo.isDeleted,
          )
        : null);

    try {
      await ChatService.uploadImageMessage(
        widget.channel.id,
        File(picked.path),
        replyToId: replyingTo?.id,
      );
    } catch (e) {
      // Remove the optimistic placeholder on failure
      if (mounted && _pendingLocalId != null) {
        final failedId = _pendingLocalId!;
        setState(() {
          _messages = _messages.where((m) => m.id != failedId).toList();
          _pendingLocalId = null;
        });
        final detail = e is ApiException ? e.message : 'Failed to send image';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(detail),
          backgroundColor: context.colors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ─── Delete message ────────────────────────────────────────────────────────

  Future<void> _deleteMessage(_Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Delete message',
          style: TextStyle(fontFamily: 'SF Pro', fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'This message will be removed for everyone.',
          style: TextStyle(fontFamily: 'SF Pro'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Optimistic remove — keep snapshot for revert
    final snapshot = List<_Message>.from(_messages);
    setState(() {
      _messages = _messages.where((m) => m.id != msg.id).toList();
    });

    try {
      await ChatService.deleteMessage(widget.channel.id, msg.id);
    } catch (_) {
      if (mounted) setState(() => _messages = snapshot);
    }
  }

  // ─── Pin message ───────────────────────────────────────────────────────────

  Future<void> _pinMessage(_Message msg) async {
    final previous = _pinnedMessage;
    setState(() => _pinnedMessage = msg);
    try {
      await ChatService.pinMessage(widget.channel.id, msg.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pinnedMessage = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : 'Failed to pin message'),
        backgroundColor: context.colors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _unpinMessage(_Message msg) async {
    final previous = _pinnedMessage;
    setState(() => _pinnedMessage = null);
    try {
      await ChatService.unpinMessage(widget.channel.id, msg.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pinnedMessage = previous);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : 'Failed to unpin message'),
        backgroundColor: context.colors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ─── Voice recording ───────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recordSeconds >= 90) {
        _stopAndPreview();
        return;
      }
      setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopAndPreview() async {
    _recordTimer?.cancel();
    final duration = _recordSeconds;
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });
    final path = await _recorder.stop();
    if (duration < 1 || path == null || !mounted) return;
    setState(() {
      _recordedPath = path;
      _recordedDuration = duration;
    });
  }

  Future<void> _sendRecorded() async {
    final path = _recordedPath;
    final duration = _recordedDuration;
    final replyingTo = _replyingTo;
    if (path == null) return;
    _stopTypingOut();

    await _disposePreviewPlayer();

    setState(() {
      _recordedPath = null;
      _recordedDuration = 0;
      _previewPlaying = false;
      _replyingTo = null;
    });

    _addLocalMessage(
      isVoice: true,
      voiceDuration: duration,
      replyTo: replyingTo != null
          ? _ReplyTo(
              id: replyingTo.id,
              senderName: replyingTo.senderName,
              text: replyingTo.text,
              isVoice: replyingTo.isVoice,
              isDeleted: replyingTo.isDeleted,
            )
          : null,
    );
    ChatService.uploadVoiceMessage(
      widget.channel.id,
      File(path),
      duration,
      replyToId: replyingTo?.id,
    ).catchError((_) {});
  }

  Future<void> _discardRecorded() async {
    final path = _recordedPath;
    await _disposePreviewPlayer();
    setState(() {
      _recordedPath = null;
      _recordedDuration = 0;
      _previewPlaying = false;
    });
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _disposePreviewPlayer() async {
    await _previewCompleteSub?.cancel();
    _previewCompleteSub = null;
    final player = _previewPlayer;
    _previewPlayer = null;
    await player?.dispose();
  }

  Future<void> _togglePreviewPlay() async {
    final path = _recordedPath;
    if (path == null) return;

    if (_previewPlaying) {
      await _previewPlayer?.pause();
      if (mounted) setState(() => _previewPlaying = false);
      return;
    }

    try {
      var player = _previewPlayer;
      if (player == null) {
        player = ap.AudioPlayer();
        _previewPlayer = player;
        _previewCompleteSub = player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _previewPlaying = false);
        });
      }
      // Resume keeps the paused position; play() restarts from the top —
      // only take the restart path the first time or after it ran to
      // completion.
      if (player.state == ap.PlayerState.paused) {
        await player.resume();
      } else {
        await player.play(ap.DeviceFileSource(path));
      }
      if (mounted) setState(() => _previewPlaying = true);
    } catch (_) {
      if (mounted) setState(() => _previewPlaying = false);
    }
  }

  // ─── Audio playback ────────────────────────────────────────────────────────

  Future<void> _togglePlayVoice(_Message msg) async {
    if (msg.voiceUrl == null) return;

    if (_playingId == msg.id) {
      _playerStateSub?.cancel();
      await _player.pause();
      setState(() => _playingId = null);
      return;
    }

    // Don't call _player.stop() here — this player is now the long-lived
    // shared instance (see _player getter above), and stop() immediately
    // followed by the setAudioSource() below (once the download finishes)
    // races just_audio's platform activation and can silently abort the
    // load on the first tap. loadAdHoc()'s setAudioSource call already
    // interrupts/replaces whatever was previously loaded.
    _playerStateSub?.cancel();
    setState(() => _playingId = msg.id);
    // Claimed before the download starts (the slow part) so a late-finishing
    // download that lost the race to a load elsewhere (Mock Test Listening,
    // a Speaking Sample, another voice message) can detect it and bail
    // instead of hijacking playback with this stale audio.
    final loadGen = PodcastPlaybackService.instance.beginLoad();

    try {
      debugPrint('[Voice] ▶ tapped id=${msg.id} url=${msg.voiceUrl}');
      setState(() => _downloadProgress[msg.id] = 0.0);

      // Stream the response so we can report real download progress instead
      // of a plain spinner. http.get buffers the whole body before returning.
      final client = http.Client();
      final http.StreamedResponse streamed;
      try {
        streamed = await client.send(http.Request('GET', Uri.parse(msg.voiceUrl!)));
      } catch (e) {
        client.close();
        rethrow;
      }
      debugPrint('[Voice] HTTP ${streamed.statusCode} '
          'content-length=${streamed.contentLength}');
      if (streamed.statusCode != 200) {
        client.close();
        throw Exception('HTTP ${streamed.statusCode}');
      }

      final total = streamed.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        received += chunk.length;
        if (total != null && total > 0 && mounted) {
          setState(() =>
              _downloadProgress[msg.id] = (received / total).clamp(0.0, 1.0));
        }
      }
      client.close();

      if (mounted) setState(() => _downloadProgress.remove(msg.id));

      final dir = await getTemporaryDirectory();
      final ext = msg.voiceUrl!.split('.').last.split('?').first;
      final file = File('${dir.path}/voice_${msg.id}.$ext');
      await file.writeAsBytes(builder.takeBytes());
      final fileSize = await file.length();
      debugPrint('[Voice] saved → ${file.path} ($fileSize bytes)');

      if (fileSize < 1000) {
        throw Exception('Audio file too small ($fileSize bytes) — likely empty recording');
      }

      if (!PodcastPlaybackService.instance.isCurrent(loadGen)) {
        // Something else claimed the shared player while we were downloading
        // (the user left for Mock Test Listening, a Speaking Sample, or
        // tapped a different voice message) — don't hijack it now.
        debugPrint('[Voice] stale load for id=${msg.id}, discarding');
        if (mounted) setState(() => _playingId = null);
        return;
      }

      debugPrint('[Voice] setAudioSource...');
      // just_audio_background is initialized globally in main.dart, which
      // requires every AudioSource to carry a MediaItem tag or setFilePath
      // throws an assertion error.
      final dur = await PodcastPlaybackService.instance.loadAdHoc(
        'voice_${msg.id}',
        Uri.file(file.path),
        title: 'Voice message',
        generation: loadGen,
      );
      if (!PodcastPlaybackService.instance.isCurrent(loadGen)) {
        debugPrint('[Voice] stale load for id=${msg.id} after setAudioSource, discarding');
        if (mounted) setState(() => _playingId = null);
        return;
      }
      // Use the actual file duration; fall back to durationStream for formats
      // that report duration asynchronously (some iOS codecs).
      final actualSeconds = (dur ?? _player.duration)?.inSeconds;
      debugPrint('[Voice] duration from setAudioSource: ${dur?.inSeconds}s  '
          'from .duration: ${_player.duration?.inSeconds}s');
      setState(() => _playTotalSeconds = actualSeconds);

      if (actualSeconds == null) {
        _player.durationStream.first.then((d) {
          debugPrint('[Voice] durationStream emitted: ${d?.inSeconds}s');
          if (d != null && mounted) setState(() => _playTotalSeconds = d.inSeconds);
        });
      }

      debugPrint('[Voice] play()');
      await _player.play();

      // playerStateStream is a BehaviorSubject: subscribing replays the
      // player's last known state first, which — if the previous track we
      // played on this shared player ran to completion — is a stale
      // "completed" left over from before this load. Skip that replay so
      // we don't immediately reset _playingId based on someone else's
      // completion.
      _playerStateSub = _player.playerStateStream.skip(1).listen((state) {
        debugPrint('[Voice] playerState: ${state.processingState} '
            'pos=${_player.position} dur=${_player.duration}');
        if (state.processingState == ProcessingState.completed &&
            mounted &&
            _reallyAtEnd()) {
          setState(() => _playingId = null);
        }
      });
    } catch (e, st) {
      debugPrint('[Voice] ERROR: $e\n$st');
      if (mounted) {
        setState(() {
          _playingId = null;
          _downloadProgress.remove(msg.id);
        });
      }
    }
  }

  // Reusing one shared AudioPlayer across rapid source swaps sometimes fires
  // a spurious ProcessingState.completed moments after play() starts (the
  // native/plugin side briefly reports stale end-of-track bookkeeping from
  // the previous source before it catches up). A genuine completion always
  // has position ≈ duration, so use that to tell the two apart instead of
  // trusting the processingState alone.
  bool _reallyAtEnd() {
    final dur = _player.duration;
    if (dur == null || dur == Duration.zero) return true;
    return _player.position >= dur - const Duration(milliseconds: 500);
  }

  Future<void> _seekVoice(Duration position) async {
    await _player.seek(position);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  // Channels where students can't post are tutor-only channels: every
  // participant is a tutor, so per-message tutor identity/moderation UI
  // (name, avatar, IELTS badge, profile tap, report, block) is redundant.
  bool get _isTutorOnlyChannel => !widget.channel.studentCanPost;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isVoiceOnly = widget.channel.type == ChannelType.voiceOnly;
    final isAnnouncement = widget.channel.type == ChannelType.announcement;
    final canPost = _currentUserIsTutor || widget.channel.studentCanPost;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: _buildAppBar(),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            if (_pinnedMessage != null)
              _PinnedBanner(
                message: _pinnedMessage!,
                onTap: () => _scrollToOriginal(_pinnedMessage!.id),
                onUnpin: _currentUserIsTutor
                    ? () => _unpinMessage(_pinnedMessage!)
                    : null,
              ),
            Expanded(
              child: Stack(
                children: [
                  _buildMessageList(),
                  if (_showReplyBadge && _pendingReplyIds.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _ReplyBadge(
                          count: _pendingReplyIds.length,
                          onTap: _onReplyBadgeTap,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _ScrollToBottomFab(
                      visible: _showScrollToBottomFab,
                      onTap: _scrollToBottomAnimated,
                    ),
                  ),
                ],
              ),
            ),
            if (_typingUsers.isNotEmpty)
              _TypingIndicator(names: _typingUsers.values.toList()),
            if (isAnnouncement)
              _AnnouncementBar()
            else if (!canPost)
              const _ReadOnlyBanner()
            else ...[
              if (_replyingTo != null)
                _ReplyBar(
                  message: _replyingTo!,
                  onDismiss: () => setState(() => _replyingTo = null),
                  onTap: () => _scrollToOriginal(_replyingTo!.id),
                ),
              isVoiceOnly
                  ? _VoiceInputBar(
                      isRecording: _isRecording,
                      recordSeconds: _recordSeconds,
                      recordedPath: _recordedPath,
                      recordedDuration: _recordedDuration,
                      previewPlaying: _previewPlaying,
                      onStartRecord: _startRecording,
                      onStopRecord: _stopAndPreview,
                      onSendRecord: _sendRecorded,
                      onDiscardRecord: _discardRecorded,
                      onPlayPreview: _togglePreviewPlay,
                      isTutor: _currentUserIsTutor,
                      onCreateQuiz:
                          _currentUserIsTutor ? _openCreateQuizSheet : null,
                      onAudioLibrary:
                          _currentUserIsTutor ? _pickAndSendAudioFile : null,
                    )
                  : _TextInputBar(
                      controller: _textController,
                      onSend: _sendText,
                      onImagePick: _pickAndSendImage,
                      isTutor: _currentUserIsTutor,
                      onCreateQuiz:
                          _currentUserIsTutor ? _openCreateQuizSheet : null,
                      onAudioLibrary:
                          _currentUserIsTutor ? _pickAndSendAudioFile : null,
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loadingInitial) {
      return _ChatSkeleton(hideIdentity: _isTutorOnlyChannel);
    }

    // Index 0 is the loading-more indicator (hidden when not loading)
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _messages.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _loadingMore
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accentBlue,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink();
        }

        final msgIdx = i - 1;
        final msg = _messages[msgIdx];
        final showDate =
            msgIdx == 0 || !_sameDay(_messages[msgIdx - 1].sentAt, msg.sentAt);

        final itemKey = _messageKeys.putIfAbsent(msg.id, GlobalKey.new);

        return AnimatedContainer(
          key: ValueKey(msg.id),
          duration: const Duration(milliseconds: 300),
          color: _highlightedId == msg.id
              ? context.colors.accentYellow.withValues(alpha: 0.15)
              : Colors.transparent,
          child: Column(
            children: [
              if (showDate) _DateDivider(date: msg.sentAt),
              _SwipeToReply(
                onReply: msg.isDeleted
                    ? null
                    : () => setState(() => _replyingTo = msg),
                child: _MessageBubble(
                  key: itemKey,
                  message: msg,
                  isPlaying: _playingId == msg.id,
                  playerTotalSeconds:
                      _playingId == msg.id ? _playTotalSeconds : null,
                  downloadProgress: _downloadProgress[msg.id],
                  voicePlayer: _playingId == msg.id ? _player : null,
                  onVoiceSeek: _playingId == msg.id ? _seekVoice : null,
                  onPlayToggle: () => _togglePlayVoice(msg),
                  onReply: () => setState(() => _replyingTo = msg),
                  onDelete: msg.isMine && !msg.isDeleted
                      ? () => _deleteMessage(msg)
                      : null,
                  onReport: !msg.isMine && !msg.isDeleted && !_isTutorOnlyChannel
                      ? () => _showReportSheet(msg)
                      : null,
                  onBlock: !msg.isMine && !_isTutorOnlyChannel
                      ? () => _confirmBlock(msg)
                      : null,
                  hideTutorIdentity: _isTutorOnlyChannel,
                  isPinned: _pinnedMessage?.id == msg.id,
                  onPin: _currentUserIsTutor ? () => _pinMessage(msg) : null,
                  onUnpin: _currentUserIsTutor ? () => _unpinMessage(msg) : null,
                  quizSubmitting: msg.quiz != null &&
                      _quizSubmitting.contains(msg.quiz!.id),
                  quizPendingOptionId: msg.quiz != null
                      ? _quizPendingOption[msg.quiz!.id]
                      : null,
                  onQuizOptionTap: msg.isQuiz
                      ? (optionId) =>
                          _submitQuizAnswer(msg.id, msg.quiz!.id, optionId)
                      : null,
                  onScrollToOriginal: _scrollToOriginal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.colors.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: 48,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        color: context.colors.textPrimary,
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.channel.emoji}  ${widget.channel.name}',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          Text(
            widget.channel.type == ChannelType.voiceOnly
                ? 'Voice only'
                : widget.channel.type == ChannelType.announcement
                    ? 'Announcements'
                    : 'Community channel',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: context.colors.border),
      ),
    );
  }
}

// ─── Date divider ──────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider({required this.date});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day} ${_months[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: context.colors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.colors.textTertiary,
              ),
            ),
          ),
          Expanded(child: Divider(color: context.colors.border)),
        ],
      ),
    );
  }
}

// ─── Loading skeleton ───────────────────────────────────────────────────────────

class _ChatSkeleton extends StatelessWidget {
  // Tutor-only channels hide per-message identity (avatar + name), so the
  // skeleton mirrors that by omitting the avatar/name placeholders.
  final bool hideIdentity;
  const _ChatSkeleton({required this.hideIdentity});

  // Mirrors the real message list: alternating incoming/outgoing bubbles with
  // varied widths and a couple of two-line bubbles so the placeholder reads as
  // a conversation rather than a block of identical bars.
  static const _rows = [
    (isMine: false, widthFactor: 0.58, lines: 2),
    (isMine: false, widthFactor: 0.42, lines: 1),
    (isMine: true, widthFactor: 0.50, lines: 1),
    (isMine: false, widthFactor: 0.66, lines: 2),
    (isMine: true, widthFactor: 0.34, lines: 1),
    (isMine: false, widthFactor: 0.46, lines: 1),
    (isMine: true, widthFactor: 0.60, lines: 2),
    (isMine: false, widthFactor: 0.38, lines: 1),
  ];

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width;
    return IgnorePointer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final row in _rows)
            _row(
              context,
              isMine: row.isMine,
              width: maxWidth * row.widthFactor,
              lines: row.lines,
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required bool isMine,
    required double width,
    required int lines,
  }) {
    final showAvatar = !isMine && !hideIdentity;
    // 44 ≈ one line of text with bubble padding; second line adds ~19.
    final bubbleHeight = lines == 2 ? 63.0 : 44.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isMine ? 64 : 16, 5, isMine ? 16 : 64, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (showAvatar) ...[
            const Skeleton(width: 32, height: 32, circle: true),
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showAvatar) ...[
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Skeleton(width: 72, height: 11, borderRadius: 4),
                ),
              ],
              Skeleton(width: width, height: bubbleHeight, borderRadius: 16),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message message;
  final bool isPlaying;
  final int? playerTotalSeconds;
  final double? downloadProgress;
  final AudioPlayer? voicePlayer;
  final void Function(Duration)? onVoiceSeek;
  final VoidCallback onPlayToggle;
  final VoidCallback onReply;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final bool quizSubmitting;
  final int? quizPendingOptionId;
  final void Function(int)? onQuizOptionTap;
  final void Function(String replyToId)? onScrollToOriginal;
  final bool hideTutorIdentity;
  final bool isPinned;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isPlaying,
    required this.onPlayToggle,
    required this.onReply,
    this.onDelete,
    this.onReport,
    this.onBlock,
    this.playerTotalSeconds,
    this.downloadProgress,
    this.voicePlayer,
    this.onVoiceSeek,
    this.quizSubmitting = false,
    this.quizPendingOptionId,
    this.onQuizOptionTap,
    this.onScrollToOriginal,
    this.hideTutorIdentity = false,
    this.isPinned = false,
    this.onPin,
    this.onUnpin,
  });

  String _timeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showActions(BuildContext context) {
    final canReply = !message.isDeleted;
    final canDelete = onDelete != null;
    final canReport = onReport != null;
    final canBlock = onBlock != null;
    final canPin = !message.isDeleted && !isPinned && onPin != null;
    final canUnpin = isPinned && onUnpin != null;
    if (!canReply && !canDelete && !canReport && !canBlock && !canPin && !canUnpin) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPin)
              ListTile(
                leading: Icon(Icons.push_pin_outlined, color: context.colors.textPrimary),
                title: Text(
                  'Pin message',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onPin!();
                },
              ),
            if (canUnpin)
              ListTile(
                leading: Icon(Icons.push_pin, color: context.colors.textPrimary),
                title: Text(
                  'Unpin message',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onUnpin!();
                },
              ),
            if (canReply)
              ListTile(
                leading: Icon(Icons.reply_rounded, color: context.colors.textPrimary),
                title: Text(
                  'Reply',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onReply();
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: context.colors.error),
                title: Text(
                  'Delete',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
                },
              ),
            if (canReport)
              ListTile(
                leading: Icon(Icons.flag_outlined, color: context.colors.textPrimary),
                title: Text(
                  'Report',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onReport!();
                },
              ),
            if (canBlock)
              ListTile(
                leading: Icon(Icons.block, color: context.colors.error),
                title: Text(
                  'Block sender',
                  style: TextStyle(fontFamily: 'SF Pro', color: context.colors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onBlock!();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizLayout(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!hideTutorIdentity) ...[
              _Avatar(
                initials: message.senderInitials,
                color: message.senderColor,
                imageUrl: message.senderAvatar,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!hideTutorIdentity)
                    GestureDetector(
                      onTap: message.isTutor && message.tutorId != null
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TutorProfileScreen(
                                      tutorId: message.tutorId!),
                                ),
                              )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.senderName,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: message.senderColor,
                              ),
                            ),
                            if (message.isTutor) ...[
                              const SizedBox(width: 6),
                              _TutorBadge(ieltsScore: message.tutorIeltsScore),
                            ],
                          ],
                        ),
                      ),
                    ),
                  _QuizBubble(
                    quiz: message.quiz!,
                    submitting: quizSubmitting,
                    pendingOptionId: quizPendingOptionId,
                    onOptionTap: onQuizOptionTap,
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _timeLabel(message.sentAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (message.isQuiz && message.quiz != null) {
      return _buildQuizLayout(context);
    }

    final isMine = message.isMine;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMine ? 16 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 16),
    );

    Widget bubbleContent;

    if (message.isImage) {
      bubbleContent = _ImageBubble(
        imageUrl: message.imageUrl,
        isMine: isMine,
        radius: radius,
        replyTo: message.replyTo,
        onScrollToOriginal: onScrollToOriginal,
      );
    } else {
      bubbleContent = Container(
        decoration: BoxDecoration(
          color: isMine ? context.colors.brand : context.colors.surfaceAlt,
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.replyTo != null)
              _ReplyBlock(
                replyTo: message.replyTo!,
                isMine: isMine,
                onTap: message.replyTo!.isDeleted
                    ? null
                    : () => onScrollToOriginal?.call(message.replyTo!.id),
              ),
            if (message.isVoice)
              _VoiceBubble(
                duration: message.voiceDuration,
                playerTotalSeconds: playerTotalSeconds,
                downloadProgress: downloadProgress,
                isMine: isMine,
                isPlaying: isPlaying,
                onPlayToggle: onPlayToggle,
                player: voicePlayer,
                onSeek: onVoiceSeek,
              )
            else
              _TextBubble(
                text: message.text ?? '',
                isMine: isMine,
                hasReply: message.replyTo != null,
              ),
          ],
        ),
      );
    }

    return GestureDetector(
      onLongPress: () => _showActions(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(isMine ? 64 : 16, 3, isMine ? 16 : 64, 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMine && !hideTutorIdentity) ...[
              _Avatar(
                initials: message.senderInitials,
                color: message.senderColor,
                imageUrl: message.senderAvatar,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine && !hideTutorIdentity)
                    GestureDetector(
                      onTap: message.isTutor && message.tutorId != null
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TutorProfileScreen(
                                    tutorId: message.tutorId!,
                                  ),
                                ),
                              )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.senderName,
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: message.senderColor,
                              ),
                            ),
                            if (message.isTutor) ...[
                              const SizedBox(width: 6),
                              _TutorBadge(ieltsScore: message.tutorIeltsScore),
                            ],
                          ],
                        ),
                      ),
                    ),
                  bubbleContent,
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      _timeLabel(message.sentAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reply block (inside bubble) ───────────────────────────────────────────────

class _ReplyBlock extends StatelessWidget {
  final _ReplyTo replyTo;
  final bool isMine;
  final VoidCallback? onTap;

  const _ReplyBlock({required this.replyTo, required this.isMine, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accentColor =
        isMine ? Colors.white.withValues(alpha: 0.55) : context.colors.accentBlue;
    final textColor = isMine
        ? Colors.white.withValues(alpha: 0.75)
        : context.colors.textSecondary;
    final bgColor = isMine
        ? Colors.white.withValues(alpha: 0.12)
        : context.colors.accentBlue.withValues(alpha: 0.08);

    Widget content;
    if (replyTo.isDeleted) {
      content = Text(
        'Message deleted',
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: textColor.withValues(alpha: 0.6),
        ),
      );
    } else if (replyTo.isImage) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            'Image',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: textColor),
          ),
        ],
      );
    } else if (replyTo.isVoice) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_rounded, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            'Voice message',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: textColor),
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyTo.senderName != null)
            Text(
              replyTo.senderName!,
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          if (replyTo.senderName != null) const SizedBox(height: 2),
          Text(
            replyTo.text ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              color: textColor,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: accentColor, width: 3),
          ),
        ),
        child: content,
      ),
    );
  }
}

// ─── Reply bar (above text input) ─────────────────────────────────────────────

class _ReplyBar extends StatelessWidget {
  final _Message message;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _ReplyBar({required this.message, required this.onDismiss, this.onTap});

  @override
  Widget build(BuildContext context) {
    final String preview;
    if (message.isDeleted) {
      preview = 'Message deleted';
    } else if (message.isQuiz) {
      preview = '📊 Quiz';
    } else if (message.isImage) {
      preview = '🖼 Image';
    } else if (message.isVoice) {
      preview = '🎵 Voice message';
    } else {
      final t = message.text ?? '';
      preview = t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 18, color: context.colors.accentBlue),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.accentBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.senderName.isEmpty ? 'You' : message.senderName,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.accentBlue,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 18, color: context.colors.textTertiary),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Pinned message banner ─────────────────────────────────────────────────────

class _PinnedBanner extends StatelessWidget {
  final _Message message;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  const _PinnedBanner({required this.message, required this.onTap, this.onUnpin});

  @override
  Widget build(BuildContext context) {
    final String preview;
    if (message.isQuiz) {
      preview = '📊 Quiz';
    } else if (message.isImage) {
      preview = '🖼 Image';
    } else if (message.isVoice) {
      preview = '🎵 Voice message';
    } else {
      final t = message.text ?? '';
      preview = t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          border: Border(bottom: BorderSide(color: context.colors.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin_rounded, size: 16, color: context.colors.accentBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pinned message',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.accentBlue,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onUnpin != null)
              GestureDetector(
                onTap: onUnpin,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 18, color: context.colors.textTertiary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final Color color;
  final String? imageUrl;
  const _Avatar({required this.initials, required this.color, this.imageUrl});

  Widget _initialsChild() {
    final display = initials.length > 2 ? initials.substring(0, 2) : initials;
    return Center(
      child: Text(
        display,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => _initialsChild(),
            )
          : _initialsChild(),
    );
  }
}

class _TextBubble extends StatelessWidget {
  final String text;
  final bool isMine;
  final bool hasReply;
  const _TextBubble({
    required this.text,
    required this.isMine,
    this.hasReply = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, hasReply ? 8 : 10, 14, 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: isMine ? context.colors.onBrand : context.colors.textPrimary,
          height: 1.45,
        ),
      ),
    );
  }
}

// ─── Image bubble ──────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final String? imageUrl;
  final bool isMine;
  final BorderRadius radius;
  final _ReplyTo? replyTo;
  final void Function(String replyToId)? onScrollToOriginal;

  const _ImageBubble({
    required this.imageUrl,
    required this.isMine,
    required this.radius,
    this.replyTo,
    this.onScrollToOriginal,
  });

  void _openFullScreen(BuildContext context) {
    if (imageUrl == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            child: Image.network(imageUrl!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: Container(
        decoration: BoxDecoration(
          color: isMine ? context.colors.brand : context.colors.surfaceAlt,
          borderRadius: radius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (replyTo != null)
              _ReplyBlock(
                replyTo: replyTo!,
                isMine: isMine,
                onTap: replyTo!.isDeleted
                    ? null
                    : () => onScrollToOriginal?.call(replyTo!.id),
              ),
            ClipRRect(
              borderRadius: replyTo != null
                  ? BorderRadius.only(
                      bottomLeft: radius.bottomLeft,
                      bottomRight: radius.bottomRight,
                    )
                  : radius,
              child: imageUrl == null
                  ? Container(
                      width: 200,
                      height: 150,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.accentBlue,
                          ),
                        ),
                      ),
                    )
                  : Image.network(
                      imageUrl!,
                      width: 220,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              width: 220,
                              height: 150,
                              alignment: Alignment.center,
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                                color: context.colors.accentBlue,
                              ),
                            ),
                      errorBuilder: (ctx, err, st) => Container(
                        width: 220,
                        height: 100,
                        alignment: Alignment.center,
                        color: context.colors.surfaceAlt,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: context.colors.textTertiary,
                          size: 32,
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

// ─── Voice bubble ──────────────────────────────────────────────────────────────

class _VoiceBubble extends StatefulWidget {
  final int duration;
  final int? playerTotalSeconds;
  final double? downloadProgress;
  final bool isMine;
  final bool isPlaying;
  final VoidCallback onPlayToggle;
  // Non-null only while this bubble is the one loaded in the shared player —
  // lets the waveform track real playback position and support seeking.
  final AudioPlayer? player;
  final void Function(Duration)? onSeek;
  const _VoiceBubble({
    required this.duration,
    required this.isMine,
    required this.isPlaying,
    required this.onPlayToggle,
    this.playerTotalSeconds,
    this.downloadProgress,
    this.player,
    this.onSeek,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  static const _waveformWidth = 110.0;

  StreamSubscription<Duration>? _positionSub;
  Duration _position = Duration.zero;
  // Fraction (0-1) of the waveform the user is currently dragging/tapping to,
  // used for immediate visual feedback ahead of the player's seek + stream.
  double? _dragFraction;

  static const _bars = [
    4, 8, 14, 10, 16, 11, 5, 18, 13, 7,
    4, 11, 15, 10, 6, 13, 9, 5, 12, 16,
    10, 6, 14, 8, 4,
  ];

  @override
  void initState() {
    super.initState();
    _subscribeToPlayer();
  }

  @override
  void didUpdateWidget(_VoiceBubble old) {
    super.didUpdateWidget(old);
    if (widget.player != old.player) {
      _positionSub?.cancel();
      _positionSub = null;
      _position = Duration.zero;
      _subscribeToPlayer();
    }
  }

  void _subscribeToPlayer() {
    final player = widget.player;
    if (player == null) return;
    _position = player.position;
    _positionSub = player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  int get _total =>
      widget.playerTotalSeconds ?? (widget.duration > 0 ? widget.duration : 0);

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _updateDragFraction(double localDx) {
    if (widget.onSeek == null || _total <= 0) return;
    setState(() => _dragFraction = (localDx / _waveformWidth).clamp(0.0, 1.0));
  }

  void _commitSeek() {
    final fraction = _dragFraction;
    if (fraction == null) return;
    setState(() => _dragFraction = null);
    if (widget.onSeek == null || _total <= 0) return;
    widget.onSeek!(
      Duration(milliseconds: (fraction * _total * 1000).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final isPlaying = widget.isPlaying;
    final fg =
        isMine ? context.colors.onBrand : context.colors.textPrimary;
    final waveBase = isMine
        ? Colors.white.withValues(alpha: 0.35)
        : context.colors.textPrimary.withValues(alpha: 0.2);
    final waveActive =
        isMine ? context.colors.onBrand : context.colors.textPrimary;

    final total = _total;
    final dragFraction = _dragFraction;
    final elapsedMs = dragFraction != null
        ? (dragFraction * total * 1000).round()
        : (isPlaying ? _position.inMilliseconds : 0);
    final fraction = total > 0
        ? (elapsedMs / (total * 1000)).clamp(0.0, 1.0)
        : 0.0;
    final activeCount = (fraction * _bars.length).round();
    final label = (isPlaying || dragFraction != null)
        ? _fmt(elapsedMs ~/ 1000)
        : _fmt(total);
    final downloading = widget.downloadProgress != null;
    final ringColor =
        isMine ? Colors.white : context.colors.accentBlue;
    final canSeek = widget.onSeek != null && total > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: widget.onPlayToggle,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.18)
                          : context.colors.textPrimary
                              .withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      downloading
                          ? Icons.hourglass_empty_rounded
                          : isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      color: fg,
                      size: 18,
                    ),
                  ),
                  if (downloading)
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        value: widget.downloadProgress! > 0
                            ? widget.downloadProgress
                            : null,
                        strokeWidth: 2.5,
                        color: ringColor,
                        backgroundColor: ringColor.withValues(alpha: 0.2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: canSeek
                    ? (d) => _updateDragFraction(d.localPosition.dx)
                    : null,
                onTapUp: canSeek ? (_) => _commitSeek() : null,
                onHorizontalDragStart: canSeek
                    ? (d) => _updateDragFraction(d.localPosition.dx)
                    : null,
                onHorizontalDragUpdate: canSeek
                    ? (d) => _updateDragFraction(d.localPosition.dx)
                    : null,
                onHorizontalDragEnd: canSeek ? (_) => _commitSeek() : null,
                child: SizedBox(
                  height: 28,
                  width: _waveformWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_bars.length, (i) {
                      final barH = _bars[i].toDouble().clamp(3.0, 20.0);
                      return Container(
                        width: 2.5,
                        height: barH,
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        decoration: BoxDecoration(
                          color: i < activeCount ? waveActive : waveBase,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Text input bar ────────────────────────────────────────────────────────────

class _TextInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onImagePick;
  final bool isTutor;
  final VoidCallback? onCreateQuiz;
  final VoidCallback? onAudioLibrary;
  const _TextInputBar({
    required this.controller,
    required this.onSend,
    required this.onImagePick,
    this.isTutor = false,
    this.onCreateQuiz,
    this.onAudioLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          if (onCreateQuiz != null)
            IconButton(
              icon: Icon(Icons.poll, color: context.colors.textTertiary),
              onPressed: onCreateQuiz,
              tooltip: 'Create Quiz',
            ),
          if (onAudioLibrary != null)
            IconButton(
              icon: Icon(Icons.headphones, color: context.colors.textTertiary),
              onPressed: onAudioLibrary,
              tooltip: 'Send MP3 file',
            ),
          IconButton(
            icon: Icon(Icons.image_outlined, color: context.colors.textTertiary),
            onPressed: onImagePick,
            tooltip: 'Send image',
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(
                    fontFamily: 'SF Pro',
                    color: context.colors.textTertiary,
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 15,
                  color: context.colors.textPrimary,
                ),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.colors.brand,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: context.colors.onBrand,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Voice input bar ───────────────────────────────────────────────────────────

class _VoiceInputBar extends StatelessWidget {
  final bool isRecording;
  final int recordSeconds;
  final String? recordedPath;
  final int recordedDuration;
  final bool previewPlaying;
  final VoidCallback onStartRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onSendRecord;
  final VoidCallback onDiscardRecord;
  final VoidCallback onPlayPreview;
  final bool isTutor;
  final VoidCallback? onCreateQuiz;
  final VoidCallback? onAudioLibrary;

  const _VoiceInputBar({
    required this.isRecording,
    required this.recordSeconds,
    required this.recordedPath,
    required this.recordedDuration,
    required this.previewPlaying,
    required this.onStartRecord,
    required this.onStopRecord,
    required this.onSendRecord,
    required this.onDiscardRecord,
    required this.onPlayPreview,
    this.isTutor = false,
    this.onCreateQuiz,
    this.onAudioLibrary,
  });

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    if (recordedPath != null) return _buildPreview(context, bottomPad);
    return _buildRecorder(context, bottomPad);
  }

  Widget _buildRecorder(BuildContext context, double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        children: [
          if (isTutor && !isRecording &&
              (onCreateQuiz != null || onAudioLibrary != null)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onCreateQuiz != null)
                  TextButton.icon(
                    onPressed: onCreateQuiz,
                    icon: const Icon(Icons.poll, size: 16),
                    label: const Text('Quiz'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                      textStyle: const TextStyle(
                          fontFamily: 'SF Pro', fontSize: 13),
                    ),
                  ),
                if (onCreateQuiz != null && onAudioLibrary != null)
                  const SizedBox(width: 8),
                if (onAudioLibrary != null)
                  TextButton.icon(
                    onPressed: onAudioLibrary,
                    icon: const Icon(Icons.headphones, size: 16),
                    label: const Text('MP3 file'),
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                      textStyle: const TextStyle(
                          fontFamily: 'SF Pro', fontSize: 13),
                    ),
                  ),
              ],
            ),
            const Divider(height: 16),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isRecording
                ? Text(
                    'Recording ${_fmt(recordSeconds)} / 01:30',
                    key: const ValueKey('rec'),
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.error,
                    ),
                  )
                : Text(
                    '🎤  Voice messages only · max 90 seconds',
                    key: const ValueKey('idle'),
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 12,
                      color: context.colors.textTertiary,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: isRecording ? onStopRecord : onStartRecord,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isRecording ? 70 : 58,
              height: isRecording ? 70 : 58,
              decoration: BoxDecoration(
                color: isRecording
                    ? context.colors.error
                    : context.colors.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isRecording
                            ? context.colors.error
                            : context.colors.brand)
                        .withValues(alpha: 0.28),
                    blurRadius: isRecording ? 20 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: isRecording ? 30 : 26,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isRecording ? 'Tap to stop' : 'Tap to record',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 11,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context, double bottomPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        children: [
          Text(
            previewPlaying
                ? 'Playing...'
                : 'Voice recorded · ${_fmt(recordedDuration)}',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PreviewBtn(
                icon: Icons.delete_outline_rounded,
                iconColor: context.colors.error,
                bg: context.colors.error,
                bgAlpha: 0.1,
                size: 50,
                label: 'delete',
                onTap: onDiscardRecord,
              ),
              const SizedBox(width: 24),
              _PreviewBtn(
                icon: previewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                iconColor: Colors.white,
                bg: previewPlaying
                    ? context.colors.accentBlue
                    : context.colors.brand,
                size: 64,
                label: previewPlaying ? 'pause' : 'listen',
                onTap: onPlayPreview,
                shadow: true,
              ),
              const SizedBox(width: 24),
              _PreviewBtn(
                icon: Icons.send_rounded,
                iconColor: Colors.white,
                bg: context.colors.brand,
                size: 50,
                label: 'send',
                onTap: onSendRecord,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final double bgAlpha;
  final double size;
  final String label;
  final VoidCallback onTap;
  final bool shadow;

  const _PreviewBtn({
    required this.icon,
    required this.iconColor,
    required this.bg,
    this.bgAlpha = 1.0,
    required this.size,
    required this.label,
    required this.onTap,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgAlpha < 1.0 ? bg.withValues(alpha: bgAlpha) : bg,
              shape: BoxShape.circle,
              boxShadow: shadow
                  ? [
                      BoxShadow(
                        color: bg.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.4),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 10,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tutor badge ───────────────────────────────────────────────────────────────

class _TutorBadge extends StatelessWidget {
  final double? ieltsScore;
  const _TutorBadge({this.ieltsScore});

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).brightness == Brightness.dark
        ? context.colors.accentYellow
        : const Color(0xFFB8860B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.accentYellow.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: context.colors.accentYellow.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TUTOR',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: gold,
              letterSpacing: 0.5,
            ),
          ),
          if (ieltsScore != null) ...[
            Container(
              width: 1,
              height: 9,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              color: gold.withValues(alpha: 0.35),
            ),
            Text(
              'IELTS ${ieltsScore!.toStringAsFixed(1)}',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: gold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Announcement bar ──────────────────────────────────────────────────────────

class _AnnouncementBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: context.colors.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            'Announcements only — only admins can post here',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Read-only banner (student in restricted channel) ─────────────────────────

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: context.colors.textTertiary),
          const SizedBox(width: 6),
          Text(
            'Only tutors can post in this channel',
            style: TextStyle(
              fontFamily: 'SF Pro',
              fontSize: 12,
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Typing indicator (below message list) ─────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final List<String> names;
  const _TypingIndicator({required this.names});

  @override
  Widget build(BuildContext context) {
    final text = names.length == 1
        ? '${names[0]} is typing...'
        : '${names.take(2).join(', ')} are typing...';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'SF Pro',
          fontSize: 12,
          color: context.colors.textTertiary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

// ─── Quiz bubble ───────────────────────────────────────────────────────────────

class _QuizBubble extends StatelessWidget {
  final _QuizData quiz;
  final bool submitting;
  final int? pendingOptionId;
  final void Function(int)? onOptionTap;

  const _QuizBubble({
    required this.quiz,
    required this.submitting,
    this.pendingOptionId,
    this.onOptionTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = quiz.totalVotes;
    final locked = quiz.hasAnswered || submitting;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📊', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    quiz.title,
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: context.colors.border),
          ...quiz.options.map((opt) {
            final fraction = total > 0 ? opt.answerCount / total : 0.0;
            final pct = (fraction * 100).round();
            final isMyAnswer = quiz.hasAnswered && quiz.myAnswerId == opt.id;
            final isPending = pendingOptionId == opt.id && submitting;
            final isCorrect = opt.isCorrect;

            final Color barColor;
            if (quiz.hasAnswered) {
              barColor = isCorrect == true
                  ? context.colors.success
                  : context.colors.border;
            } else if (isPending) {
              barColor = context.colors.accentBlue;
            } else {
              barColor = context.colors.border;
            }

            final Widget leadIcon;
            if (locked && quiz.hasAnswered) {
              leadIcon = Icon(
                isCorrect == true
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 18,
                color: isCorrect == true
                    ? context.colors.success
                    : context.colors.error,
              );
            } else {
              leadIcon = Icon(
                Icons.radio_button_unchecked_rounded,
                size: 18,
                color: isPending
                    ? context.colors.accentBlue
                    : context.colors.textTertiary,
              );
            }

            return GestureDetector(
              onTap: !locked ? () => onOptionTap?.call(opt.id) : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(width: 22, child: leadIcon),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  opt.text,
                                  style: TextStyle(
                                    fontFamily: 'SF Pro',
                                    fontSize: 14,
                                    color: context.colors.textPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (isMyAnswer) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: context.colors.accentBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            fontFamily: 'SF Pro',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${opt.answerCount}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: 'SF Pro',
                              fontSize: 12,
                              color: context.colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fraction,
                        backgroundColor: context.colors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$total vote${total == 1 ? '' : 's'} total',
                style: TextStyle(
                  fontFamily: 'SF Pro',
                  fontSize: 12,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Create quiz sheet ─────────────────────────────────────────────────────────

class _CreateQuizSheet extends StatefulWidget {
  final String slug;
  const _CreateQuizSheet({required this.slug});

  @override
  State<_CreateQuizSheet> createState() => _CreateQuizSheetState();
}

class _CreateQuizSheetState extends State<_CreateQuizSheet> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [];
  int _correctIndex = -1;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _questionController.addListener(_onTextChanged);
    _addController();
    _addController();
  }

  void _addController() {
    final c = TextEditingController();
    c.addListener(_onTextChanged);
    _optionControllers.add(c);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _questionController.removeListener(_onTextChanged);
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.removeListener(_onTextChanged);
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_questionController.text.trim().isEmpty) return false;
    if (_correctIndex < 0 || _correctIndex >= _optionControllers.length) {
      return false;
    }
    return _optionControllers.every((c) => c.text.trim().isNotEmpty);
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _addController());
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final removed = _optionControllers.removeAt(index);
    removed.removeListener(_onTextChanged);
    removed.dispose();
    if (_correctIndex == index) {
      _correctIndex = -1;
    } else if (_correctIndex > index) {
      _correctIndex--;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final options = List.generate(
        _optionControllers.length,
        (i) => {
          'text': _optionControllers[i].text.trim(),
          'is_correct': i == _correctIndex,
        },
      );
      await ChatService.createQuiz(
        widget.slug,
        title: _questionController.text.trim(),
        options: options,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(e is ApiException ? e.message : 'Failed to create quiz'),
        backgroundColor: context.colors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Text(
                  'New Quiz',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: context.colors.textTertiary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── scrollable form ─────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Question',
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: 'Type your question...',
                      hintStyle: TextStyle(
                        fontFamily: 'SF Pro',
                        color: context.colors.textTertiary,
                        fontSize: 15,
                      ),
                      filled: true,
                      fillColor: context.colors.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: context.colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: context.colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: context.colors.accentBlue),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    style: TextStyle(
                      fontFamily: 'SF Pro',
                      fontSize: 15,
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Options',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(tap ○ to mark correct)',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 12,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_optionControllers.length, (i) {
                    final isCorrect = _correctIndex == i;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () =>
                                setState(() => _correctIndex = i),
                            child: Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCorrect
                                    ? context.colors.success
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isCorrect
                                      ? context.colors.success
                                      : context.colors.textTertiary,
                                  width: 2,
                                ),
                              ),
                              child: isCorrect
                                  ? const Icon(Icons.check_rounded,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _optionControllers[i],
                              decoration: InputDecoration(
                                hintText: 'Option ${i + 1}...',
                                hintStyle: TextStyle(
                                  fontFamily: 'SF Pro',
                                  color: context.colors.textTertiary,
                                  fontSize: 14,
                                ),
                                filled: true,
                                fillColor: context.colors.surfaceAlt,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                      color: context.colors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: isCorrect
                                        ? context.colors.success
                                            .withValues(alpha: 0.5)
                                        : context.colors.border,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                      color: context.colors.accentBlue),
                                ),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                              ),
                              style: TextStyle(
                                fontFamily: 'SF Pro',
                                fontSize: 14,
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          if (_optionControllers.length > 2)
                            IconButton(
                              icon: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: context.colors.error,
                                  size: 20),
                              onPressed: () => _removeOption(i),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (_optionControllers.length < 6)
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add option'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.accentBlue,
                        textStyle: const TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // ── send button ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + safeBottom),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.brand,
                  disabledBackgroundColor: context.colors.border,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Send Quiz',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Swipe-to-reply wrapper ────────────────────────────────────────────────────

class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReply;
  const _SwipeToReply({required this.child, this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _threshold = 56.0;
  double _drag = 0;
  bool _triggered = false;
  late AnimationController _springController;
  late Animation<double> _spring;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() {}));
    _spring = const AlwaysStoppedAnimation(0);
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  double get _offset => _drag > 0 ? _drag : _spring.value;

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.onReply == null) return;
    if (d.delta.dx > 0) {
      _springController.stop();
      setState(() {
        _drag = (_drag + d.delta.dx).clamp(0, _threshold + 20);
        if (_drag >= _threshold && !_triggered) {
          _triggered = true;
          widget.onReply!();
        }
      });
    }
  }

  void _onDragEnd(DragEndDetails _) {
    _spring = Tween<double>(begin: _drag, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOut),
    );
    _drag = 0;
    _triggered = false;
    _springController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final dx = _offset;
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (dx > 0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Opacity(
                  opacity: (dx / _threshold).clamp(0, 1),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * (dx / _threshold).clamp(0, 1),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: context.colors.accentBlue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        color: context.colors.accentBlue,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ─── Report sheet ──────────────────────────────────────────────────────────────

class _ReportSheet extends StatefulWidget {
  final Future<void> Function(String reason, String comment) onSubmit;
  const _ReportSheet({required this.onSubmit});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = [
    ('spam', 'Spam'),
    ('inappropriate', 'Inappropriate content'),
    ('harassment', 'Harassment or bullying'),
    ('other', 'Other'),
  ];

  String? _selectedReason;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_selectedReason!, _commentController.text.trim());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Text(
                  'Report message',
                  style: TextStyle(
                    fontFamily: 'SF Pro',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.colors.textTertiary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._reasons.map((r) {
            final (value, label) = r;
            final selected = _selectedReason == value;
            return InkWell(
              onTap: () => setState(() => _selectedReason = value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? context.colors.accentBlue
                              : context.colors.textTertiary,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Center(
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.accentBlue,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'SF Pro',
                        fontSize: 15,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Additional comment (optional)',
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _commentController,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                hintText: 'Tell us more...',
                hintStyle: TextStyle(
                  fontFamily: 'SF Pro',
                  color: context.colors.textTertiary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: context.colors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.colors.accentBlue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
              style: TextStyle(
                fontFamily: 'SF Pro',
                fontSize: 14,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + safeBottom),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_selectedReason != null && !_submitting)
                    ? _submit
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.brand,
                  disabledBackgroundColor: context.colors.border,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Send report',
                        style: TextStyle(
                          fontFamily: 'SF Pro',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── @ Reply badge ─────────────────────────────────────────────────────────────

class _ReplyBadge extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _ReplyBadge({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.brand,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '@',
              style: TextStyle(
                color: context.colors.accentBlue,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro',
              ),
            ),
            const SizedBox(width: 6),
            Text(
              count == 1 ? '1 new reply' : '$count new replies',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro',
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ScrollToBottomFab extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;
  const _ScrollToBottomFab({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: AnimatedScale(
          scale: visible ? 1 : 0.6,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
