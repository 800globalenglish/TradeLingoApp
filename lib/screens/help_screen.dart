import 'package:flutter/material.dart';
import '../services/resource_strings.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<Map<String, String>> _faqKeys = [
    {'question': 'aiadd4021', 'answer': 'aiadd4022'},
    {'question': 'aiadd4023', 'answer': 'aiadd4024'},
    {'question': 'aiadd4025', 'answer': 'aiadd4026'},
    {'question': 'aiadd4027', 'answer': 'aiadd4028'},
    {'question': 'aiadd4029', 'answer': 'aiadd4030'},
    {'question': 'aiadd4031', 'answer': 'aiadd4032'},
    {'question': 'aiadd4033', 'answer': 'aiadd4034'},
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
          ..._faqKeys.map(
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
          // Contact support - separate entry since the answer combines
          // a resource string (label) with a hardcoded email address
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Card(
              color: Colors.white.withOpacity(0.08),
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                iconColor: Colors.white,
                collapsedIconColor: Colors.white70,
                title: Text(
                  rs.get('aiadd4035'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${rs.get('aiadd2195')}: app@800globalenglish.com',
                        style: const TextStyle(color: Colors.white70),
                      ),
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