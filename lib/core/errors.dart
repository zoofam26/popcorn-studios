/// Base class for user-facing application errors.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: $message';
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

class ApiAuthException extends AppException {
  const ApiAuthException(super.message, {super.cause});
}

class EngineException extends AppException {
  const EngineException(super.message, {super.cause});
}

class MetadataTimeoutException extends EngineException {
  const MetadataTimeoutException(super.message, {super.cause});
}

class RpcException extends AppException {
  const RpcException(super.message, {this.code, super.cause});

  final int? code;
}
