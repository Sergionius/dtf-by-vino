sealed class AppFailure {
  const AppFailure(this.message);

  final String message;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Нет подключения к сети']);
}

final class TimeoutFailure extends AppFailure {
  const TimeoutFailure([super.message = 'Сервер не ответил вовремя']);
}

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = 'Требуется авторизация']);
}

final class ServerFailure extends AppFailure {
  const ServerFailure({required this.statusCode, required String message})
    : super(message);

  final int statusCode;
}

final class ParsingFailure extends AppFailure {
  const ParsingFailure([super.message = 'Не удалось обработать ответ сервера']);
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Произошла неизвестная ошибка']);
}
