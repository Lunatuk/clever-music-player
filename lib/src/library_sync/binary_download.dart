/// Fixed codes only: exceptions never retain a signed URL, headers or OS text.
enum BinaryDownloadFailure {
  invalidAddress,
  closed,
  busy,
  quotaExceeded,
  cancelled,
  timeout,
  network,
  unauthorized,
  accessDenied,
  notFound,
  rateLimited,
  invalidResponse,
  tooLarge,
  incomplete,
  unsafePath,
  storage,
}

final class BinaryDownloadException implements Exception {
  const BinaryDownloadException(this.failure);
  final BinaryDownloadFailure failure;
  @override
  String toString() => 'BinaryDownloadException(${failure.name})';
}

final class BinaryDownloadProgress {
  const BinaryDownloadProgress(this.receivedBytes, this.totalBytes);
  final int receivedBytes;
  final int? totalBytes;
}

const maximumRawDownloadBytes = 8 * 1024 * 1024 * 1024;
