import 'package:flutter/material.dart';
import '../services/resource_strings.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  // Each section: a header key, followed by its list of {question, answer} keys.
  static const List<Map<String, dynamic>> _faqSections = [
    {
      'header': 'aiadd4039', // Subscription & Purchasing
      'items': [
        {'question': 'aiadd4037', 'answer': 'aiadd4038'},
      ],
    },
    {
      'header': 'aiadd4040', // Account & Sharing
      'items': [
        {'question': 'aiadd4041', 'answer': 'aiadd4042'},
        {'question': 'aiadd4027', 'answer': 'aiadd4028'},
      ],
    },
    {
      'header': 'aiadd4043', // Downloading & Offline Use
      'items': [
        {'question': 'aiadd4021', 'answer': 'aiadd4022'},
        {'question': 'aiadd4023', 'answer': 'aiadd4024'},
        {'question': 'aiadd4031', 'answer': 'aiadd4032'},
      ],
    },
    {
      'header': 'aiadd4044', // Quizzes, Oral Exams & Progress
      'items': [
        {'question': 'aiadd4025', 'answer': 'aiadd4026'},
        {'question': 'aiadd4045', 'answer': 'aiadd4046'},
        {'question': 'aiadd4029', 'answer': 'aiadd4030'},
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
          for (final section in _faqSections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                rs.get(section['header'] as String),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ...(section['items'] as List<Map<String, String>>).map(
                  (faq) => Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: Card(
                  color: Colors.white.withOpacity(0.08),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    iconColor: Colors.white,
                    collapsedIconColor: Colors.white70,
                    title: Text(
                      rs.get(faq['question']!),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            rs.get(faq['answer']!),
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
