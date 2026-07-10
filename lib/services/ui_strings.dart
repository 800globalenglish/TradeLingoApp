// Simple translated text lookup for the app's own button labels/screens.
// Add more languages/keys here as translations become available -
// anything missing automatically falls back to English.
class UiStrings {
  static const Map<String, Map<String, String>> _strings = {
    'en-US': {
      'myLessons': 'My Lessons',
      'pdfs': 'PDFs',
      'manageVideoDownloads': 'Manage Video Downloads',
      'offlineContent': 'Offline Content (Words/Audio)',
    },
    'zh-CN': {
      'myLessons': '我的课程',
      'pdfs': 'PDF文件',
      'manageVideoDownloads': '管理视频下载',
      'offlineContent': '离线内容（单词/音频）',
    },
    'zh-HK': {
      'myLessons': '我的課程',
      'pdfs': 'PDF檔案',
      'manageVideoDownloads': '管理影片下載',
      'offlineContent': '離線內容（單字/音頻）',
    },
    'ko-KR': {
      'myLessons': '내 수업',
      'pdfs': 'PDF',
      'manageVideoDownloads': '비디오 다운로드 관리',
      'offlineContent': '오프라인 콘텐츠 (단어/오디오)',
    },
    'vi-VN': {
      'myLessons': 'Bài học của tôi',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Quản lý tải video',
      'offlineContent': 'Nội dung ngoại tuyến (Từ vựng/Âm thanh)',
    },
    'ja-JP': {
      'myLessons': '私のレッスン',
      'pdfs': 'PDF',
      'manageVideoDownloads': '動画ダウンロードの管理',
      'offlineContent': 'オフラインコンテンツ（単語/オーディオ）',
    },
    'ru-RU': {
      'myLessons': 'Мои уроки',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Управление загрузкой видео',
      'offlineContent': 'Офлайн-контент (слова/аудио)',
    },
    'es-ES': {
      'myLessons': 'Mis lecciones',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Gestionar descargas de vídeo',
      'offlineContent': 'Contenido sin conexión (Palabras/Audio)',
    },
    'de-DE': {
      'myLessons': 'Meine Lektionen',
      'pdfs': 'PDFs',
      'manageVideoDownloads': 'Videodownloads verwalten',
      'offlineContent': 'Offline-Inhalte (Wörter/Audio)',
    },
    'th-TH': {
      'myLessons': 'บทเรียนของฉัน',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'จัดการการดาวน์โหลดวิดีโอ',
      'offlineContent': 'เนื้อหาออฟไลน์ (คำศัพท์/เสียง)',
    },
    'hi-IN': {
      'myLessons': 'मेरी लेसन्स',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'वीडियो डाउनलोड प्रबंधित करें',
      'offlineContent': 'ऑफ़लाइन सामग्री (शब्द/ऑडियो)',
    },
    'fr-FR': {
      'myLessons': 'Mes leçons',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Gérer les téléchargements de vidéos',
      'offlineContent': 'Contenu hors ligne (Mots/Audio)',
    },
    'it-IT': {
      'myLessons': 'Le mie lezioni',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Gestisci download video',
      'offlineContent': 'Contenuti offline (Parole/Audio)',
    },
    'pt-PT': {
      'myLessons': 'As minhas lições',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Gerir descargas de vídeo',
      'offlineContent': 'Conteúdo offline (Palavras/Áudio)',
    },
    'fil-PH': {
      'myLessons': 'Mga Lesson Ko',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Pamahalaan ang Video Downloads',
      'offlineContent': 'Offline Content (Mga Salita/Audio)',
    },
    'he-IL': {
      'myLessons': 'השיעורים שלי',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'ניהול הורדות וידאו',
      'offlineContent': 'תוכן לא מקוון (מילים/אודיו)',
    },
    'ar-SA': {
      'myLessons': 'دروسي',
      'pdfs': 'ملفات PDF',
      'manageVideoDownloads': 'إدارة تنزيلات الفيديو',
      'offlineContent': 'المحتوى دون اتصال (كلمات/صوت)',
    },
    'uk-UA': {
      'myLessons': 'Мої уроки',
      'pdfs': 'PDF',
      'manageVideoDownloads': 'Керувати завантаженням відео',
      'offlineContent': 'Офлайн-контент (Слова/Аудіо)',
    },
  };

  static String get(String languageCode, String key) {
    return _strings[languageCode]?[key] ?? _strings['en-US']![key] ?? key;
  }
}