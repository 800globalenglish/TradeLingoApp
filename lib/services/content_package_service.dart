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

// NEW — the full/paid package is split into two smaller zips instead of one
// large one. A single ~38MB zip was intermittently getting corrupted or
// truncated during upload through the CDN's browser dashboard; splitting
// sounds and images into their own files keeps each upload well under
// whatever size threshold was causing that. The free package was never
// affected and stays a single zip, unchanged.
const String fullSoundsZipUrl = 'https://cdn.800globalenglish.com/content/mobileZip/sounds.zip';
const String fullImagesZipUrl = 'https://cdn.800globalenglish.com/content/mobileZip/images.zip';

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

  // CHANGED — for the paid tier this now sums BOTH zip files' sizes, since
  // the full package is downloaded as two separate files.
  Future<int?> getRemoteZipSizeBytes({required bool isPaid}) async {
    try {
      if (!isPaid) {
        final response = await http.head(Uri.parse(freeZipUrl));
        final contentLength = response.headers['content-length'];
        return contentLength != null ? int.tryParse(contentLength) : null;
      }

      final soundsResponse = await http.head(Uri.parse(fullSoundsZipUrl));
      final imagesResponse = await http.head(Uri.parse(fullImagesZipUrl));
      final soundsLength = int.tryParse(soundsResponse.headers['content-length'] ?? '');
      final imagesLength = int.tryParse(imagesResponse.headers['content-length'] ?? '');
      if (soundsLength == null || imagesLength == null) return null;
      return soundsLength + imagesLength;
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

  // Public entry point wraps the real attempt in a retry loop. A large
  // download over a flaky connection (or, as we found, a large upload that
  // never landed cleanly on the CDN) can produce a corrupted/truncated zip
  // that only reveals itself once we try to decode it. Rather than making
  // the person notice "failed" and manually tap the button again, we detect
  // that specific failure ourselves and silently retry once before giving
  // up for real.
  Future<bool> downloadAndExtract({
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    int? knownTotalBytes,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = await _downloadAndExtractOnce(
        onDownloadProgress: onDownloadProgress,
        onStatus: onStatus,
        knownTotalBytes: knownTotalBytes,
      );

      if (result) return true;

      if (attempt < maxAttempts) {
        // ignore: avoid_print
        print('DEBUG downloadAndExtract: attempt $attempt failed, retrying...');
        onStatus?.call('retrying');
      }
    }
    return false;
  }

  Future<bool> _downloadAndExtractOnce({
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    int? knownTotalBytes,
  }) async {
    // Tracked outside the try block so the catch handler below can clean it
    // up if extraction fails partway through.
    Directory? tempDir;

    try {
      onStatus?.call('checking');
      final isPaidResult = await checkIsPaidNow();
      final prefs = await SharedPreferences.getInstance();
      final downloadedTier = prefs.getString('contentPackageTier');
      final isPaid = isPaidResult ?? (downloadedTier == 'full');
      final versionUrl = isPaid ? fullVersionUrl : freeVersionUrl;

      final baseDir = await getApplicationSupportDirectory();
      tempDir = Directory('${baseDir.path}/content-package-tmp');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      if (isPaid) {
        // Full/paid package: two separate zips, downloaded and extracted
        // one after another into the same temp folder (they populate
        // different subfolders - sounds/ and images/ - so there's no
        // overlap). If EITHER one fails or is corrupted, the whole attempt
        // fails and the outer retry loop tries both again from scratch.
        final combinedKnownTotal = knownTotalBytes ?? await getRemoteZipSizeBytes(isPaid: true) ?? 0;

        int bytesReceivedSoFar = 0;

        await _downloadAndExtractSingleZip(
          url: fullSoundsZipUrl,
          tempDir: tempDir,
          overallTotalBytes: combinedKnownTotal,
          bytesAlreadyCounted: bytesReceivedSoFar,
          onBytesReceivedUpdate: (n) => bytesReceivedSoFar = n,
          onDownloadProgress: onDownloadProgress,
          onStatus: onStatus,
          downloadingStatusCode: 'downloading_sounds',
          extractingStatusCode: 'extracting_sounds',
        );

        await _downloadAndExtractSingleZip(
          url: fullImagesZipUrl,
          tempDir: tempDir,
          overallTotalBytes: combinedKnownTotal,
          bytesAlreadyCounted: bytesReceivedSoFar,
          onBytesReceivedUpdate: (n) => bytesReceivedSoFar = n,
          onDownloadProgress: onDownloadProgress,
          onStatus: onStatus,
          downloadingStatusCode: 'downloading_images',
          extractingStatusCode: 'extracting_images',
        );
      } else {
        // Free package: unchanged, single zip.
        final freeTotal = knownTotalBytes ?? await getRemoteZipSizeBytes(isPaid: false) ?? 0;
        await _downloadAndExtractSingleZip(
          url: freeZipUrl,
          tempDir: tempDir,
          overallTotalBytes: freeTotal,
          bytesAlreadyCounted: 0,
          onBytesReceivedUpdate: (_) {},
          onDownloadProgress: onDownloadProgress,
          onStatus: onStatus,
          downloadingStatusCode: 'downloading',
          extractingStatusCode: 'extracting',
        );
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
      // ignore: avoid_print
      print('DEBUG downloadAndExtract failed: $e');
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

  // Downloads one zip, verifies its size matches what the server promised,
  // decodes it, and extracts it directly into tempDir. Throws on any
  // failure (size mismatch, corrupted zip, etc.) so the caller's try/catch
  // and retry logic handles it uniformly, whether this is the only zip
  // (free tier) or one of two (paid tier).
  Future<void> _downloadAndExtractSingleZip({
    required String url,
    required Directory tempDir,
    required int overallTotalBytes,
    required int bytesAlreadyCounted,
    required void Function(int totalBytesReceivedSoFar) onBytesReceivedUpdate,
    void Function(DownloadProgress progress)? onDownloadProgress,
    void Function(String status)? onStatus,
    required String downloadingStatusCode,
    required String extractingStatusCode,
  }) async {
    onStatus?.call(downloadingStatusCode); // fires as THIS specific file starts
    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    final streamedResponse = await client.send(request);

    if (streamedResponse.statusCode != 200) {
      client.close();
      throw Exception('HTTP ${streamedResponse.statusCode} for $url');
    }

    final thisFileTotal = streamedResponse.contentLength ?? 0;
    final bytesBuilder = BytesBuilder(copy: false);
    int bytesReceivedThisFile = 0;

    final stopwatch = Stopwatch()..start();

    await for (final chunk in streamedResponse.stream) {
      bytesBuilder.add(chunk);
      bytesReceivedThisFile += chunk.length;

      final combinedReceived = bytesAlreadyCounted + bytesReceivedThisFile;
      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
      double? estimatedRemaining;
      if (elapsedSeconds > 0.5 && bytesReceivedThisFile > 0 && overallTotalBytes > 0) {
        // FIXED — use THIS file's own bytes/time for the speed calculation,
        // not the combined total (which includes bytes from a previous file
        // downloaded with a different stopwatch). Using the combined count
        // against only this file's elapsed time made the calculated speed
        // look artificially huge right as the second file started, causing
        // "time remaining" to collapse to ~1 second and stay stuck there.
        final bytesPerSecond = bytesReceivedThisFile / elapsedSeconds;
        final remainingBytes = overallTotalBytes - combinedReceived;
        estimatedRemaining = remainingBytes / bytesPerSecond;
      }

      final progress = DownloadProgress(
        bytesReceived: combinedReceived,
        totalBytes: overallTotalBytes,
        estimatedSecondsRemaining: estimatedRemaining,
      );
      // ignore: avoid_print
      print('DEBUG progress ($url): received=$combinedReceived total=$overallTotalBytes percent=${progress.percent}');
      onDownloadProgress?.call(progress);
    }

    client.close();
    stopwatch.stop();

    // Verify the download actually matches the size the server promised,
    // BEFORE attempting to decode it. Catches an obviously truncated
    // transfer early, with a clear reason, rather than letting it fall
    // through to the zip decoder's more cryptic error.
    if (thisFileTotal > 0 && bytesReceivedThisFile != thisFileTotal) {
      throw Exception('Size mismatch for $url: received=$bytesReceivedThisFile expected=$thisFileTotal');
    }

    onBytesReceivedUpdate(bytesAlreadyCounted + bytesReceivedThisFile);

    onStatus?.call(extractingStatusCode); // file-specific extraction status

    final zipBytes = bytesBuilder.takeBytes();

    // Decoding is wrapped separately so a corrupted/incomplete zip (e.g.
    // "Could not find End of Central Directory Record") reads as a clean,
    // catchable failure rather than an uncaught crash.
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw Exception('Zip decode failed for $url: $e');
    }

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
