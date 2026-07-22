# Feed architecture: implementation plan

> Базовая ветка: `refactor/architecture-foundation`, созданная от `feature/security-and-scroll`.
> До merge PR #4 ветка остаётся локальной. После merge переносим собственные коммиты через `rebase --onto upstream/main feature/security-and-scroll`.

## Общие правила

- Каждый этап заканчивается компилируемым проектом.
- Не менять визуальный дизайн и API behavior без необходимости.
- Не мигрировать comments, chats, auth и write endpoints на новый client.
- Не использовать code generation.
- Не использовать `dynamic post` после завершения миграции.
- Не включать generated build artifacts.
- После каждого этапа запускать `flutter analyze --no-pub` и релевантные tests.

## Этап 1. Quality baseline

### 1.1 Исправить analyzer info

Файлы:

- `lib/util/json_safe.dart`;
- `lib/screens/chat_screen.dart`;
- `lib/screens/feed_screen.dart`;
- `lib/screens/post_screen.dart`;
- `lib/screens/user_profile_screen.dart`;
- `lib/widgets/avatar.dart`;
- `lib/widgets/badges.dart`;
- `lib/widgets/blocks/block_view.dart`;
- `lib/widgets/gif_picker.dart`;
- `lib/widgets/media_view.dart`;
- `lib/widgets/post_card.dart`;
- `lib/widgets/reactions.dart`.

Действия:

- заменить deprecated или лишние callback-параметры корректными `_`;
- исправить `use_build_context_synchronously` через `mounted` checks;
- заменить dangling library doc comment обычным комментарием либо добавить library declaration;
- не выполнять массовое форматирование несвязанных участков.

Проверка:

```bash
flutter analyze --fatal-infos --no-pub
```

Коммит:

```text
chore: enforce Flutter analyzer checks
```

### 1.2 Добавить baseline test infrastructure

Файлы:

- `test/helpers/fixtures.dart`;
- `test/helpers/pump_app.dart`;
- `test/widgets/comment_thread_test.dart`;
- `test/widgets/linkified_text_test.dart`.

Действия:

- вынести минимальные JSON fixtures;
- протестировать flatten, depth, descendant count и collapse;
- протестировать обновление `LinkifiedText` при смене input;
- не тестировать приватные Flutter implementation details recognizer напрямую.

Проверка:

```bash
flutter test
```

Коммит:

```text
test: add baseline widget infrastructure
```

## Этап 2. Core API primitives

### 2.1 Типизированные ошибки и Result

Новые файлы:

- `lib/core/api/app_failure.dart`;
- `lib/core/api/result.dart`.

Реализовать sealed hierarchy:

- `NetworkFailure`;
- `TimeoutFailure`;
- `UnauthorizedFailure`;
- `ServerFailure` с status code и безопасным message;
- `ParsingFailure`;
- `UnknownFailure`.

`Result<T>` содержит `Success<T>` и `Failure<T>`. Добавить безопасные helpers `valueOrNull`, pattern matching либо `fold` только если они реально упрощают callers.

### 2.2 ApiClient и HttpApiClient

Новые файлы:

- `lib/core/api/api_client.dart`;
- `lib/core/api/http_api_client.dart`.

Изменить:

- `lib/api/api_config.dart`, только если нужен публичный URL builder;
- `lib/services/settings_service.dart`, только для чтения auth token через узкую функцию/provider.

Интерфейс Feed-потребностей:

```dart
abstract interface class ApiClient {
  Future<Result<Object?>> get(
    String path, {
    String? apiVersion,
  });
}
```

`HttpApiClient` получает:

- `http.Client`;
- token provider callback;
- base URL/version configuration;
- timeout.

Классифицировать `SocketException`, `TimeoutException`, HTTP 401/403, 5xx, malformed JSON и unexpected exceptions. Не логировать production secrets.

Тесты:

- `test/core/api/http_api_client_test.dart`;
- fake/mock `http.Client` через `MockClient` из `http/testing.dart`;
- success, timeout, network, unauthorized, server, malformed body.

Коммит:

```text
refactor: add typed API result and client
```

## Этап 3. Типизированные модели Post

### 3.1 Базовые модели

Новые файлы:

- `lib/models/post.dart`;
- `lib/models/user.dart`;
- `lib/models/subsite.dart`;
- `lib/models/reaction.dart`;
- `lib/models/media_attachment.dart` при необходимости.

Использовать существующие defensive helpers из `lib/util/json_safe.dart`.

`Post.fromJson` должен:

- требовать корректный `id`;
- безопасно читать title, text, URL, date и flags;
- парсить author/subsite/counters/reactions;
- парсить blocks через существующий `parseBlock`;
- сохранять unmodifiable copy исходного JSON в `rawJson`;
- возвращать понятную parsing error через отдельный factory/result adapter.

Не дублировать `Block`: существующий `lib/models/block.dart` становится post block model. Уточнить его типы и заменить `MediaItem.raw dynamic` на безопасный map/model там, где это не ломает `MediaView`.

Добавить `copyWith` для локальных optimistic UI состояний:

- favorite state;
- reactions.

### 3.2 Тесты моделей

Файлы:

- `test/models/post_test.dart`;
- `test/fixtures/post_full.json` при необходимости;
- inline fixture для malformed/partial cases.

Проверить:

- полный post;
- минимальный post;
- numeric strings;
- отсутствующие optional fields;
- неизвестный block;
- отсутствие/некорректный ID;
- immutable collections;
- reaction copyWith.

Коммит:

```text
refactor: introduce typed post models
```

## Этап 4. Миграция post consumers

### 4.1 DtfApi compatibility methods

Изменить `lib/api/dtf_api.dart`:

- перенести старый `FeedPage` позже в feature models;
- добавить единый helper parsing списка постов;
- `getEntry` возвращает `Future<Post?>`;
- `searchEntries` возвращает `Future<List<Post>>`;
- `getSubsiteEntries` возвращает typed page;
- post bookmarks и drafts преобразуются в `Post` на API boundary;
- comment bookmarks и другие dynamic entities остаются без изменений.

Нельзя проглатывать parsing одного повреждённого item так, чтобы пропал весь список. Повреждённый item пропускается совместимыми legacy methods; новый Feed repository возвращает `ParsingFailure`, если response shape целиком невалиден.

### 4.2 PostCard

Изменить `lib/widgets/post_card.dart`:

- `final Post post`;
- заменить map indexing properties модели;
- preview text/media получать из typed blocks;
- favorite и reactions хранить в локальном immutable state;
- optimistic reaction применять к локальной копии, rollback без JSON encode/decode;
- top comment оставить dynamic comment, но не записывать `_topComment` в immutable post map;
- обновлять локальное state в `didUpdateWidget`, если изменился post ID/data.

Сохранить текущий `getTopComment` behavior.

### 4.3 PostScreen

Изменить `lib/screens/post_screen.dart`:

- `Post? postData`;
- `Post? _post`;
- typed access к author, blocks, counters и reactions;
- favorite/reaction mutation через `_post = _post.copyWith(...)`;
- comments и attachments остаются dynamic;
- body использует существующие typed `Block`.

### 4.4 Остальные экраны

Изменить:

- `lib/screens/search_screen.dart` — `List<Post> _results`;
- `lib/screens/bookmarks_screen.dart` — разделить post bookmarks и comment bookmarks; parse post wrapper;
- `lib/screens/drafts_screen.dart` — `List<Post>`;
- `lib/screens/user_profile_screen.dart` — `List<Post> _posts`;
- `lib/screens/feed_screen.dart` временно использовать typed posts до controller migration;
- `lib/services/settings_service.dart` — `isFiltered(Post post)`;
- `lib/widgets/profile_navigation.dart`, `avatar.dart`, `badges.dart` — использовать typed user/subsite там, где они вызываются из Post, сохранив compatibility для comment/profile data при необходимости.

Поиск после миграции:

```bash
rg "dynamic post|post\['|postData.*dynamic|List<dynamic> _posts" lib
```

Коммит:

```text
refactor: migrate post consumers to typed models
```

## Этап 5. Feed repository

### 5.1 Feed models

Новые файлы:

- `lib/features/feed/models/feed_type.dart`;
- `lib/features/feed/models/feed_page.dart`;
- при необходимости `feed_cursor.dart`.

`FeedType` заменяет строковые значения `popular/new/my/editorial` и хранит только API mapping, не UI labels.

`FeedPage` содержит immutable `List<Post>`, `lastId`, opaque `lastSortingValue` и `hasMore`.

### 5.2 Repository interface и implementation

Новые файлы:

- `lib/features/feed/data/feed_repository.dart`;
- `lib/features/feed/data/dtf_feed_repository.dart`.

Repository получает `ApiClient`, `SettingsService`/filter dependency и batch size provider. Реализует:

- regular feed paths;
- editorial feed path;
- opaque pagination cursor;
- filtering;
- timeline/news unwrap;
- `Result<FeedPage>`.

Удалить Feed-specific parsing из `DtfApi` после миграции всех callers либо оставить короткий deprecated adapter, если он нужен UserProfile.

Тесты:

- `test/features/feed/data/dtf_feed_repository_test.dart`;
- path/query для каждого FeedType;
- popular/new/my/editorial;
- cursor preservation;
- news unwrap;
- filtering;
- malformed timeline.

Коммит:

```text
refactor: add typed Feed repository
```

## Этап 6. Feed controller и UI

### 6.1 FeedState и controller

Новые файлы:

- `lib/features/feed/presentation/feed_state.dart`;
- `lib/features/feed/presentation/feed_controller.dart`.

Controller API:

```dart
Future<void> load();
Future<void> refresh();
Future<void> loadMore();
Future<void> retryInitial();
Future<void> retryPagination();
```

Требования:

- отдельный instance на вкладку;
- generation ID для stale requests;
- no duplicate pagination;
- popular editorial digest загружается параллельно;
- refresh сохраняет существующий контент;
- pagination error не очищает posts;
- `my` без auth не делает HTTP-запрос;
- одноразовое refresh error event не остаётся постоянным полем UI state либо имеет consume API.

### 6.2 Dependency injection

Изменить `lib/main.dart`:

- создать/предоставить общий `HttpApiClient`;
- создать `DtfFeedRepository`;
- корректно закрыть client через Provider dispose;
- сохранить существующий `SettingsService` provider.

Предпочесть `Provider<ApiClient>` и `ProxyProvider`/constructor injection. Не использовать service locator.

### 6.3 Feed UI

Изменить `lib/screens/feed_screen.dart`:

- заменить tuple строкового type на `FeedType`;
- каждый FeedList создаёт свой `FeedController`;
- использовать `context.select` для минимальных rebuild;
- удалить API calls, cursors и mutable posts из State;
- scroll listener вызывает controller `loadMore`;
- pull-to-refresh вызывает controller `refresh`;
- initial failure view с retry;
- pagination failure footer с retry;
- refresh failure SnackBar;
- unauthenticated `my` state сохраняет текущий текст входа.

Тесты:

- `test/features/feed/presentation/feed_controller_test.dart`;
- `test/features/feed/presentation/feed_screen_test.dart`.

Коммиты:

```text
refactor: move Feed state into controllers
test: cover Feed repository and controller
```

## Этап 7. Secure storage migration test

Чтобы тестировать миграцию без platform channel:

- выделить узкий secure token store interface либо injectable wrapper;
- сохранить public API `SettingsService.load()`;
- добавить fake secure store и fake preferences;
- проверить migration success, secure token priority, write failure и delete ordering.

Файлы:

- `lib/services/settings_service.dart`;
- возможно `lib/services/token_storage.dart`;
- `test/services/settings_service_test.dart`.

Не выполнять архитектурное разделение всего SettingsService в этом PR.

Коммит:

```text
test: cover secure token migration
```

## Этап 8. CI

Новый файл:

- `.github/workflows/flutter.yml`.

Triggers:

- pull requests;
- pushes в `main`.

Steps:

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build web --release
```

Использовать pinned stable Flutter version, совместимую с SDK constraint проекта. Включить pub cache через action. Не добавлять secrets.

Коммит:

```text
ci: validate Flutter analyze tests and Web build
```

## Этап 9. Финальная проверка

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build web --release
flutter build ios --simulator --no-codesign
git diff --check
```

Проверить вручную:

- все четыре Feed tabs;
- refresh и pagination;
- offline initial load и retry;
- offline pagination;
- Search, Bookmarks, Drafts, UserProfile;
- открытие PostScreen из каждого источника;
- favorite/reaction optimistic update и rollback;
- popular comment;
- GIF/video behavior из PR #4;
- login migration после rebase.

## Подготовка PR после merge #4

```bash
git fetch upstream
git switch refactor/architecture-foundation
git rebase --onto upstream/main feature/security-and-scroll
git push -u origin refactor/architecture-foundation
```

Перед push убедиться, что diff не содержит повторно commits PR #4 и локальные CDT/Firebase файлы.
