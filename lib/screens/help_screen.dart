import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/resource_strings.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  // NEW — email shown in the "How do I delete my account?" answer.
  // Address confirmed by Richard.
  static const String deleteAccountEmail = 'deleteme@800globalenglish.com';

  // NEW — safety catch: while deleteAccountEmail is still the placeholder,
  // any RELEASE build (App Store / Play Store) fails to compile on the
  // releaseGuard line. Debug builds (flutter run) still work. If you see a
  // build error pointing here, set deleteAccountEmail above first.
  static const String _emailPlaceholder = 'DELETE_ACCOUNT_EMAIL_TBD';
  static const int _guardDivisor =
      (kReleaseMode && deleteAccountEmail == _emailPlaceholder) ? 0 : 1;
  static const int releaseGuard = 1 ~/ _guardDivisor;

  // NEW — text that lives in the app instead of on the server (English only
  // for now). Looked up by key just like server strings.
  static const Map<String, String> _appText = {
    'tlDeleteAccountQ': 'How do I delete my account?',
    'tlDeleteAccountA':
        'To delete your account and all its data, email $deleteAccountEmail '
        'from the address on your account and ask us to delete it.',
  };

  // NEW — iOS only. Apple doesn't allow the app to point people to the
  // website to buy, subscribe or sign up, so on iOS these are hidden or
  // replaced. Matched by key, so server wording changes can't undo it.
  // Android is unaffected.
  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  static const Set<String> _iosHiddenSections = {'aiadd4091'}; // purchase/subscription question
  static const Set<String> _iosHiddenQuestions = {'aiadd4053'}; // "subscription expires"
  static const Set<String> _iosHiddenAnswerParts = {'aiadd4072'}; // "The website takes you all the way."
  static const Map<String, String> _iosAnswerOverrides = {
    'aiadd4042': 'You may not share your login with anyone outside your household.',
  };

  // Each section: a header key, followed by its list of {question, answer} keys.
  // CHANGED — an item can now be {'answer': key} with NO 'question' — in
  // that case the section's header itself becomes the expandable dropdown
  // trigger, and there's no separate bold header line above it (since the
  // header IS the tappable row now).
  static const List<Map<String, dynamic>> _faqSections = [
    {
      'header': 'aiadd4091', // Subscription & Purchasing
      'items': [
        {'question': 'aiadd4037', 'answer': 'aiadd4038'},
      ],
    },
    {
      'header': 'aiadd4040', // Account & Sharing
      'items': [
        {'question': 'aiadd4041', 'answer': 'aiadd4042'},
        {'question': 'tlDeleteAccountQ', 'answer': 'tlDeleteAccountA'}, // NEW
      ],
    },
    {
      'header': 'Privacy', // Account & Sharing
      'items': [
        {'question': 'aiadd4041', 'answer': 'aiadd4042'},
      ],
    },
    {
      'header': 'aiadd4044', // Quizzes, Oral Exams & Progress
      'items': [
        {'question': 'aiadd4067', 'answer': 'aiadd4068'},
        {'question': 'aiadd4025', 'answer': 'aiadd4026'},
        {'question': 'aiadd4069', 'answer': 'aiadd4070 aiadd4072'},
      ],
    },

    {
      'header': 'aiadd4092',
      'items': [
        {'answer': 'aiadd4093'},
      ],
    },
    {
      'header': 'aiadd4094',
      'items': [
        {'answer': 'aiadd4095'},
      ],
    },
    {
      'header': 'aiadd4096',
      'items': [
        {'answer': 'aiadd4097'},
      ],
    },
    {
      'header': 'aiadd4098',
      'items': [
        {'answer': 'aiadd4099'},
      ],
    },
    {
      'header': 'aiadd4100',
      'items': [
        {'answer': 'aiadd4101'},
      ],
    },
    {
      'header': 'aiadd4052', // Policies & Copyright
      'items': [
        {'question': 'aiadd4053', 'answer': 'aiadd4060'},
        {'question': 'aiadd4055', 'answer': 'aiadd4056'},
        {'question': 'aiadd4057', 'answer': 'aiadd4058'},
      ],
    },
    {
      'header': 'aiadd4047', // Login & Technical Support
      'items': [
        {'question': 'aiadd4048', 'answer': 'aiadd4049'},
        {'question': 'aiadd4050', 'answer': 'aiadd4051'},
      ],
    },
  ];

  // NEW — the sections to show: all of them on Android; on iOS, minus the
  // hidden sections/questions (and any section left with no items).
  List<Map<String, dynamic>> _visibleSections() {
    if (!_isIOS) return _faqSections;
    final visible = <Map<String, dynamic>>[];
    for (final section in _faqSections) {
      if (_iosHiddenSections.contains(section['header'])) continue;
      final items = (section['items'] as List)
          .cast<Map<String, String>>()
          .where((faq) => !_iosHiddenQuestions.contains(faq['question']))
          .toList();
      if (items.isEmpty) continue;
      visible.add({'header': section['header'], 'items': items});
    }
    return visible;
  }

  // NEW — looks up one key: iOS replacement first, then app text, then the
  // server string.
  String _text(ResourceStrings rs, String key) {
    if (_isIOS && _iosAnswerOverrides.containsKey(key)) return _iosAnswerOverrides[key]!;
    return _appText[key] ?? rs.get(key);
  }

  // Joins one or more space-separated resource keys in an answer field into
  // paragraphs, same as before (on iOS, hidden paragraphs are skipped).
  String _resolveAnswer(ResourceStrings rs, String answerField) {
    return answerField
        .split(' ')
        .where((key) => !(_isIOS && _iosHiddenAnswerParts.contains(key)))
        .map((key) => _text(rs, key))
        .join('\n\n');
  }

  Widget _answerCard(ResourceStrings rs, String answerKey) {
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: Card(
        color: Colors.white.withOpacity(0.08),
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _resolveAnswer(rs, answerKey),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResourceStrings.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF002E52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF002E52),
        title: Text(ResourceStrings.instance.get('aiadd2148')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in _visibleSections()) ...[
                () {
              final items = (section['items'] as List).cast<Map<String, String>>();
              final headerKey = section['header'] as String;

              // NEW — a section with exactly one item that has NO
              // 'question' key: the header itself becomes the expandable
              // dropdown trigger, its answer is the content. No separate
              // bold header line, no crash from a missing question key.
              if (items.length == 1 && !items.first.containsKey('question')) {
                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: Card(
                    color: Colors.white.withOpacity(0.08),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      iconColor: Colors.white,
                      collapsedIconColor: Colors.white70,
                      title: Text(
                        rs.get(headerKey),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _resolveAnswer(rs, items.first['answer']!),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Normal case — bold header, then one ExpansionTile per
              // question/answer pair underneath it.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      rs.get(headerKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...items.map(
                        (faq) => Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Card(
                        color: Colors.white.withOpacity(0.08),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ExpansionTile(
                          iconColor: Colors.white,
                          collapsedIconColor: Colors.white70,
                          title: Text(
                            _text(rs, faq['question']!),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _resolveAnswer(rs, faq['answer']!),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }(),
          ],
          // Closing note — plain text, not a Q&A, so it isn't wrapped in an ExpansionTile
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 24),
            child: Text(
              rs.get('aiadd4059'),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
