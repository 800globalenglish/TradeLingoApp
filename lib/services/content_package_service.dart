import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';
import 'api_service.dart';

// FIXED — this used to be a separately hardcoded production URL
// ('https://www.800globalenglish.com/MobileApi/GetMembershipStatus'),
// completely independent of api_service.dart's baseUrl. Whenever baseUrl
// got switched between dev and production (which happened repeatedly during
// testing), this constant silently stayed pointed at production regardless.
// That meant a token issued by one server would get checked against a
// DIFFERENT server here, which doesn't recognize it — so membership checks
// silently failed and paid accounts showed as "Free Member" even though the
// login itself was working fine. Now it always uses the same server as the
// rest of the app, so it's structurally impossible for this to drift again.
String get membershipStatusUrl => '$baseUrl/MobileApi/GetMembershipStatus';

const String freeVersionUrl = 'https://cdn.800globalenglish.com/content/mobileZip/version-free.txt';
const String freeZipUrl = 'https://cdn.800globalenglish.com/content/mobileZip/content-package-free.zip';

const String fullVersionUrl = 'https://cdn.800globalenglish.com/content/mobileZip/version.txt';
const String fullZipUrl = 'https://cdn.800globalenglish.com/content/mobileZip/content-package.zip';

class DownloadProgress {
  final int bytesReceived;
  final int totalBytes;
  final double? estimatedSecondsRemaining;

  DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    this.estimatedSecondsRemaining,
  });

  double get percent => totalBytes > 0 ? bytesReceived / totalBytes : 0;
  double get megabytesReceived => bytesReceived / (1024 * 1024);
  double get totalMegabytes => totalBytes / (1024 * 1024);
}

class ContentPackageService {
  static final ContentPackageService instance = ContentPackageService._internal();
  ContentPackageService._internal();

  bool _isContentAvailableLocally = false;
  bool get isContentAvailableLocally => _isContentAvailableLocally;

  Future<void> loadLocalStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isContentAvailableLocally = prefs.getBool('contentPackageDownloaded') ?? false;
  }

  Future<Directory> _getContentDir() async {
    final dir = await getApplicationSupportDirectory();
    final contentDir = Directory('${dir.path}/content-package');
    if (!await contentDir.exists()) {
      await contentDir.create(recursive: true);
    }
    return contentDir;
  }

  // FIXED — now returns bool? instead of bool. Previously, both "confirmed
  // free" and "couldn't check at all" (offline, server error, etc.) returned
  // false identically — so a paid member with a flaky connection would
  // incorrectly see "Welcome Free Member!" just because the check failed,
  // not because they're actually on the free tier.
  //
  // Return values:
  //   true  = confirmed paid
  //   false = confirmed free (no token = not logged in, or server said so)
  //   null  = could NOT be determined (offline, server error) — callers
  //           should fall back to the last known status, not assume free.
  Future<bool?> checkIsPaidNow() async {
    try {
      final apiService = ApiService();
      final token = await apiService.getSavedToken();
      if (token == null) return false; // genuinely not logged in - this really is "free"

      final response = await http.get(Uri.parse('$membershipStatusUrl?token=$token'));
      if (response.statusCode != 200) return null; // couldn't verify

      final data = response.body;
      return data.contains('"isPaid":true');
    } catch (e) {
      return null; // couldn't verify (e.g. offline)
    }
  }

  Future<int?> getRemoteZipSizeBytes({required bool isPaid}) async {
    try {
      final url = isPaid ? fullZipUrl : freeZipUrl;
      final response = await http.head(Uri.parse(url));
      final contentLength = response.headers['content-length'];
      return contentLength != null ? int.tryParse(contentLength) : null;
    } catch (e) {
      return null;
    }
  }

  // Checks BOTH version AND whether the person's paid tier has changed
  // since their last download (e.g. upgraded from free to paid).
  Future<bool> isUpdateAvailable() async {
    try {
      final isPaidResult = await checkIsPaidNow();
      final prefs = await SharedPreferences.getInstance();
      final downloadedTier = prefs.getString('contentPackageTier');

      // FIXED — if we couldn't verify (null), fall back to the last known
      // tier instead of silently treating it as free.
      final isPaidNow = isPaidResult ?? (downloadedTier == 'full');

      // Tier changed (e.g. upgraded to paid) - always needs a fresh download
      final currentTier = isPaidNow ? 'full' : 'free';
      if (downloadedTier != null && downloadedTier != currentTier) return true;

      final localVersion = prefs.getInt('contentPackageVersion') ?? 0;
      final versionUrl = isPaidNow ? fullVersionUrl : freeVersionUrl;

      final response = await http.get(Uri.parse(versionUrl));
      if (response.statusCode != 200) return false;

      final serverVersion = int.tryParse(response.body.trim()) ?? 0;
      return serverVersion > localVersion;
    } catch (e) {
      return false;
    }
  }

  Future<bool> downloadAndExtract({
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    int? knownTotalBytes,
  }) async {
    // NEW — tracked outside the try block so the catch handler below can
    // clean it up if extraction fails partway through.
    Directory? tempDir;

    try {
      onStatus?.call('checking');
      final isPaidResult = await checkIsPaidNow();
      final prefs = await SharedPreferences.getInstance();
      final downloadedTier = prefs.getString('contentPackageTier');
      // FIXED — fall back to last known tier if status couldn't be verified,
      // instead of silently downloading the free package for a paid member.
      final isPaid = isPaidResult ?? (downloadedTier == 'full');
      final zipUrl = isPaid ? fullZipUrl : freeZipUrl;
      final versionUrl = isPaid ? fullVersionUrl : freeVersionUrl;

      onStatus?.call('downloading');

      final request = http.Request('GET', Uri.parse(zipUrl));
      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        client.close();
        return false;
      }

      final totalBytes = streamedResponse.contentLength ?? knownTotalBytes ?? 0;
      final bytesBuilder = BytesBuilder(copy: false);
      int bytesReceived = 0;

      final stopwatch = Stopwatch()..start();

      await for (final chunk in streamedResponse.stream) {
        bytesBuilder.add(chunk);
        bytesReceived += chunk.length;

        final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        double? estimatedRemaining;
        if (elapsedSeconds > 0.5 && bytesReceived > 0 && totalBytes > 0) {
          final bytesPerSecond = bytesReceived / elapsedSeconds;
          final remainingBytes = totalBytes - bytesReceived;
          estimatedRemaining = remainingBytes / bytesPerSecond;
        }

        final progress = DownloadProgress(
          bytesReceived: bytesReceived,
          totalBytes: totalBytes,
          estimatedSecondsRemaining: estimatedRemaining,
        );
// ignore: avoid_print
        print('DEBUG progress: received=$bytesReceived total=$totalBytes percent=${progress.percent}');
        onDownloadProgress?.call(progress);
      }

      client.close();
      stopwatch.stop();

      onStatus?.call('extracting');
      final zipBytes = bytesBuilder.takeBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // FIXED — atomic swap. Previously this deleted the OLD content
      // directory before writing any new files, so if the download or
      // extraction failed partway through (network drop, app killed,
      // interrupted rebuild, etc.), the old working content was already
      // gone AND contentPackageDownloaded never got reset to false — so
      // the app kept reporting "up to date" while images/audio were
      // actually missing or incomplete.
      //
      // Now: extract into a temporary folder first. Only once EVERY file
      // has been written successfully do we delete the old folder and
      // rename the temp one into its place. If anything throws before
      // that point, the old content is never touched, and the catch
      // block below cleans up the incomplete temp folder.
      final baseDir = await getApplicationSupportDirectory();
      tempDir = Directory('${baseDir.path}/content-package-tmp');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      for (final file in archive) {
        final filePath = '${tempDir.path}/${file.name}';
        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      // Every file extracted successfully - now safe to swap.
      final contentDir = await _getContentDir();
      if (await contentDir.exists()) {
        await contentDir.delete(recursive: true);
      }
      await tempDir.rename(contentDir.path);
      tempDir = null; // renamed successfully - nothing left to clean up

      final versionResponse = await http.get(Uri.parse(versionUrl));
      final newVersion = int.tryParse(versionResponse.body.trim()) ?? 0;

      await prefs.setInt('contentPackageVersion', newVersion);
      await prefs.setBool('contentPackageDownloaded', true);
      await prefs.setString('contentPackageTier', isPaid ? 'full' : 'free');

      _isContentAvailableLocally = true;
      onStatus?.call('done');
      return true;
    } catch (e) {
      // NEW — clean up any incomplete temp extraction so it doesn't linger
      // as orphaned partial data taking up storage.
      try {
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // best-effort cleanup only
      }
      onStatus?.call('failed');
      return false;
    }
  }

  Future<String?> resolveLocalPath(String remoteUrl) async {
    if (!_isContentAvailableLocally) return null;

    final contentDir = await _getContentDir();
    String? relativePath;

    if (remoteUrl.contains('/content/media/images/lessons48/')) {
      final filename = remoteUrl.split('/').last;
      relativePath = 'images/lesson48/$filename';
    } else if (remoteUrl.contains('/content/media/sounds/lessons48/')) {
      final filename = remoteUrl.split('/').last;
      relativePath = 'sounds/lesson48/$filename';
    } else if (remoteUrl.contains('/content/media/sounds/LessonNoun/')) {
      final filename = remoteUrl.split('/').last;
      relativePath = 'sounds/LessonNoun/$filename';
    }

    if (relativePath == null) return null;

    final localFile = File('${contentDir.path}/$relativePath');
    final exists = await localFile.exists();
    return exists ? localFile.path : null;
  }
}
