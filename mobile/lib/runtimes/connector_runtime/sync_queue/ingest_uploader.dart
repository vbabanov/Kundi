abstract class IngestUploader {
  Future<void> uploadBundle({
    required String accessToken,
    required Map<String, dynamic> payload,
  });
}
