# Постепенное улучшение архитектуры и тестируемости приложения

## GitHub Issue

### Проблема

По мере роста проекта экраны начали объединять несколько ответственностей:

- отображение UI;
- загрузку данных;
- пагинацию;
- обработку ошибок;
- преобразование API JSON;
- изменение бизнес-состояния.

Некоторые файлы превысили 700–1000 строк, а значительная часть API работает через `dynamic` и статические методы. Это усложняет поддержку и повышает риск runtime-ошибок.

Предлагается не переписывать приложение целиком и не менять Provider на BLoC, а постепенно улучшать текущую архитектуру небольшими независимыми PR.

### Предлагаемые изменения

- Исправить предупреждения анализатора и добавить CI.
- Ввести единую модель API-ошибок.
- Сделать сетевой слой подменяемым в тестах.
- Постепенно добавить типизированные модели API.
- Выделить repositories и feature controllers.
- Оставить Provider для dependency injection и наблюдения за состоянием.
- Разделить `SettingsService` по ответственности.
- Декомпозировать наиболее крупные экраны.
- Добавить базовые unit/widget-тесты.

### Не является целью

- полная миграция на BLoC/Riverpod;
- обязательная замена `http` на Dio;
- одномоментное переписывание приложения;
- изменение существующего UI.

### Ожидаемый результат

- экраны отвечают преимущественно за UI;
- сетевой слой можно подменить;
- ошибки сети не превращаются молча в `null`;
- основные API-данные типизированы;
- новые функции можно добавлять без дальнейшего роста файлов на 1000+ строк;
- архитектурные изменения проходят небольшими reviewable PR.

---

## Implementation plan

### Этап 1. Базовое качество и CI

Отдельный PR:

1. Исправить `use_build_context_synchronously`, `dangling_library_doc_comments` и `unnecessary_underscores`.
2. Добавить GitHub Actions с командами:

   ```bash
   flutter pub get
   flutter analyze --fatal-infos
   flutter test
   ```

3. Создать минимальную тестовую инфраструктуру.
4. Не смешивать этот PR с функциональными изменениями.

### Этап 2. Единая модель ошибок

Добавить типизированные ошибки:

```dart
sealed class AppFailure {
  const AppFailure();
}

class NetworkFailure extends AppFailure {}
class TimeoutFailure extends AppFailure {}
class UnauthorizedFailure extends AppFailure {}
class ServerFailure extends AppFailure {}
class ParsingFailure extends AppFailure {}
```

И общий результат:

```dart
sealed class Result<T> {}

class Success<T> extends Result<T> {
  final T value;
}

class Failure<T> extends Result<T> {
  final AppFailure error;
}
```

Постепенно заменить возврат `null`, пустых списков и пустые `catch (_) {}`. Начать с одного feature, например Feed.

### Этап 3. Подменяемый API client

Ввести интерфейс:

```dart
abstract interface class ApiClient {
  Future<Result<dynamic>> get(String path);
  Future<Result<dynamic>> post(String path, {Object? body});
}
```

Текущую реализацию оставить на пакете `http`. Общие обязанности клиента:

- base URL;
- токен авторизации;
- timeout;
- decoding;
- классификация HTTP-ошибок;
- логирование в debug.

Dio рассматривать отдельно, только если понадобятся interceptors, cancellation или upload progress.

### Этап 4. Feature repositories

Добавлять постепенно:

```text
lib/features/feed/
  data/feed_repository.dart
  models/feed_item.dart
  presentation/feed_controller.dart
  presentation/feed_screen.dart

lib/features/comments/
lib/features/auth/
lib/features/profile/
lib/features/chat/
```

Первым мигрировать Feed как относительно изолированный feature.

```dart
abstract interface class FeedRepository {
  Future<Result<FeedPage>> loadPage(...);
}
```

### Этап 5. Контроллеры состояния

Не менять Provider на BLoC. Добавить feature-level `ChangeNotifier`:

```dart
class FeedController extends ChangeNotifier {
  final FeedRepository repository;

  FeedState state;
  Future<void> load();
  Future<void> loadMore();
  Future<void> refresh();
}
```

Экран должен отображать `FeedState`, передавать пользовательские действия контроллеру и не вызывать API напрямую.

Аналогично позже добавить `PostController`, `CommentsController`, `ProfileController` и `ChatController`.

### Этап 6. Разделить SettingsService

Разбить текущий глобальный объект:

```text
AuthService
PreferencesService
CurrentUserService
NotificationService
```

`SettingsService` временно оставить facade, чтобы не менять все экраны одним PR.

### Этап 7. Типизированные модели

Приоритет:

1. `User`;
2. `Post`;
3. `Comment`;
4. `Reaction`;
5. `Channel`;
6. `Message`.

Парсинг держать на data-слое:

```dart
final comment = CommentDto.fromJson(json);
```

Для нестабильного reverse-engineered API предусмотреть безопасные fallback-значения.

### Этап 8. Декомпозиция UI

Разделить крупные файлы:

- `post_screen.dart`;
- `editor_screen.dart`;
- `comment_widget.dart`;
- `dtf_api.dart`.

Выносить законченные компоненты и логику, а не дробить UI механически:

```text
PostHeader
PostBody
CommentComposer
CommentList
ReactionBar
AttachmentPicker
```

### Этап 9. Тесты

Минимальный набор:

- parsing DTO;
- пагинация;
- классификация API-ошибок;
- состояния controller: loading/success/error;
- optimistic reactions rollback;
- миграция токена;
- построение дерева комментариев.

## Критерии готовности

- CI запускается для каждого PR.
- В новых features нет прямых статических вызовов `DtfApi` из экранов.
- Ошибки API представлены типами, а не только `null`.
- Feed и Comments имеют подменяемые repositories.
- Основные модели не используют `dynamic`.
- Provider остаётся механизмом DI и наблюдения за состоянием.
- Рефакторинг выполняется серией небольших PR.
