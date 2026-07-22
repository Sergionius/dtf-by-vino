# Типизированная архитектура Feed

## Контекст

Экран Feed одновременно отвечает за UI, сетевые запросы, пагинацию, фильтрацию, обработку ошибок и хранение состояния. Данные постов передаются между API и виджетами как `dynamic`, а статический `DtfApi` нельзя подменить в unit-тестах.

Цель первого архитектурного PR — типизировать посты во всём приложении и вынести Feed в тестируемые client/repository/controller слои. Остальные features продолжат использовать совместимый `DtfApi` до последующей миграции.

Ветка рефакторинга основывается на `feature/security-and-scroll`. После merge этого PR её собственные коммиты будут перенесены на актуальный `upstream/main` через `rebase --onto`.

## Цели

- убрать `dynamic post` из приложения;
- добавить ручные immutable-модели поста и связанных сущностей;
- ввести типизированные ошибки и `Result<T>`;
- сделать HTTP client и Feed repository подменяемыми;
- перенести loading, refresh и pagination из UI в `FeedController`;
- показывать контекстные ошибки и retry;
- добавить unit/widget-тесты и обязательный CI;
- сохранить текущий UI и Provider.

## Не входит

- полная замена статического `DtfApi`;
- миграция comments, reactions, auth, chats и write-операций на новый client;
- замена Provider на BLoC или Riverpod;
- полное моделирование каждого поля DTF API;
- изменение дизайна экранов.

## Структура

```text
lib/core/api/
  api_client.dart
  http_api_client.dart
  app_failure.dart
  result.dart

lib/features/feed/
  data/
    feed_repository.dart
    dtf_feed_repository.dart
  models/
    feed_page.dart
    feed_type.dart
  presentation/
    feed_controller.dart
    feed_state.dart

lib/models/
  post.dart
  user.dart
  subsite.dart
  post_block.dart
  media_attachment.dart
  reaction.dart
```

## API client

`ApiClient` задаёт подменяемый интерфейс GET-запросов Feed. `HttpApiClient` получает `http.Client` через конструктор и отвечает за:

- построение URL;
- headers и token;
- timeout;
- JSON decoding;
- классификацию HTTP и transport ошибок;
- закрытие `http.Client`.

Остальные endpoints временно остаются в `DtfApi`.

## Result и ошибки

```dart
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  final T value;
}

final class Failure<T> extends Result<T> {
  final AppFailure error;
}
```

Поддерживаемые ошибки:

- `NetworkFailure`;
- `TimeoutFailure`;
- `UnauthorizedFailure`;
- `ServerFailure`;
- `ParsingFailure`;
- `UnknownFailure`.

Repository и controller не используют `null` как признак ошибки.

## Модели

Модели реализуются вручную без code generation. Они immutable и имеют безопасные `fromJson`.

`Post` содержит типизированные поля, реально используемые приложением:

- ID;
- title и text;
- date;
- author и subsite;
- blocks;
- reactions;
- counters;
- favorite state.

На время миграции `Post` сохраняет `rawJson` как compatibility escape hatch для ещё не типизированных вложенных данных. Новый Feed-код не должен обращаться к `rawJson`.

Объект без корректного ID не создаётся и приводит к `ParsingFailure`. Некритичные отсутствующие поля используют nullable-значения или безопасные fallback.

`PostBlock` является sealed hierarchy для известных типов: text, media, header, quote, list и unknown. Неизвестный тип блока сохраняется в `UnknownPostBlock` и не ломает parsing всего поста.

Тип `Post` используется во всех post consumers:

- Feed и editorial digest;
- `PostCard`;
- `PostScreen`;
- Search;
- Bookmarks;
- Drafts, если объект post-compatible;
- Profile и UserProfile;
- Navigator arguments.

Комментарии, уведомления и сообщения не маскируются под `Post`.

## Feed repository

`FeedRepository` предоставляет типизированную загрузку страницы:

```dart
Future<Result<FeedPage>> loadPage({
  required FeedType type,
  FeedCursor? cursor,
});
```

`DtfFeedRepository` отвечает за Feed endpoints, pagination cursors и преобразование JSON в `Post`. Фильтрация пользовательских настроек выполняется в одном согласованном слое, а не в UI.

## Feed controller

Каждая вкладка (`popular`, `new`, `my`, `editorial`) получает собственный `FeedController`. Controller создаётся рядом с `FeedList`, сохраняется вместе с вкладкой и использует общий repository.

Immutable `FeedState` содержит:

- posts;
- editorial digest;
- initial loading;
- refresh;
- loading more;
- has more;
- initial failure;
- pagination failure.

Controller реализует `load`, `refresh`, `loadMore` и `retry`. Он блокирует параллельную pagination. Generation/request ID не позволяет позднему ответу старого запроса перезаписать более новое состояние.

## Data flow

```text
FeedList
  -> FeedController
  -> FeedRepository
  -> ApiClient
  -> Result<FeedPage>
  -> FeedState
  -> UI
```

`FeedScreen` не вызывает API и не хранит pagination cursors. UI только отображает state и передаёт пользовательские действия controller.

## Ошибки в UI

- ошибка первой загрузки: отдельное состояние с сообщением и retry;
- ошибка pagination: уже загруженные посты остаются, внизу появляется retry footer;
- ошибка refresh: текущий контент остаётся, UI показывает одноразовый `SnackBar`;
- «Моя лента» без token: предложение войти без HTTP-запроса.

Автоматический retry не добавляется.

## Тесты

Unit tests:

- успешные и ошибочные ответы `HttpApiClient`;
- network, timeout, unauthorized, server и malformed JSON;
- полный и частичный `Post`;
- неизвестные block types;
- Feed repository parsing и cursors;
- controller load, refresh, pagination и retry;
- блокировка параллельного `loadMore`;
- сохранение контента при ошибках;
- игнорирование устаревших ответов;
- миграция secure-storage token;
- flatten/collapse комментариев;
- обновление `LinkifiedText`.

Widget tests Feed:

- initial loading;
- success list;
- initial error и retry;
- pagination error footer;
- «Моя лента» без авторизации.

## CI

GitHub Actions запускается на Ubuntu:

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build web --release
```

До включения `--fatal-infos` исправляются существующие lint info без функциональных изменений.

## Последовательность коммитов

1. `chore: enforce Flutter quality checks`
2. `test: add baseline test infrastructure`
3. `refactor: add typed API result and client`
4. `refactor: introduce typed post models`
5. `refactor: migrate post consumers to typed models`
6. `refactor: add feed repository`
7. `refactor: move feed state into controllers`
8. `test: cover feed repository and controller`
9. `ci: validate Flutter analyze tests and web build`

После каждого вертикального среза проект должен компилироваться. В финале проверяются analyze, tests, Web release и iOS Simulator.
