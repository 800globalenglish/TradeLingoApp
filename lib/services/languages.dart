// Shared list of supported languages - used by both the first-time wizard
// and the splash screen's language dropdown, so they always stay in sync.
const Map<String, String> appLanguages = {
  'en-US': 'English',
  'zh-CN': '中文（简体）',
  'zh-HK': '中文（繁体）',
  'ko-KR': '한국어',
  'vi-VN': 'Tiếng Việt',
  'ja-JP': '日本語',
  'ru-RU': 'Pусский',
  'es-ES': 'Español',
  'de-DE': 'Deutsch',
  'th-TH': 'ภาษา',
  'hi-IN': 'हिंदी',
  'fr-FR': 'French',
  'it-IT': 'Italiano',
  'pt-PT': 'Português',
  'fil-PH': 'Filipino',
  'he-IL': 'עברית',
  'ar-SA': 'العربية',
  'uk-UA': 'Українська',
};

// Flag emoji for each language, shown next to the name in dropdowns.
const Map<String, String> appLanguageFlags = {
  'en-US': '🇺🇸',
  'zh-CN': '🇨🇳',
  'zh-HK': '🇭🇰',
  'ko-KR': '🇰🇷',
  'vi-VN': '🇻🇳',
  'ja-JP': '🇯🇵',
  'ru-RU': '🇷🇺',
  'es-ES': '🇪🇸',
  'de-DE': '🇩🇪',
  'th-TH': '🇹🇭',
  'hi-IN': '🇮🇳',
  'fr-FR': '🇫🇷',
  'it-IT': '🇮🇹',
  'pt-PT': '🇵🇹',
  'fil-PH': '🇵🇭',
  'he-IL': '🇮🇱',
  'ar-SA': '🇸🇦',
  'uk-UA': '🇺🇦',
};