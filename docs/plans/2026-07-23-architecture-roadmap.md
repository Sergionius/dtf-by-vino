# Architecture roadmap

## 1. Цель

Целевая зависимость feature-кода:

```text
UI
  → Controller / immutable State
  → Repository
  → ApiClient
  → DTF API
```

Обратный поток данных:

```text
JSON
  → parser / DTO
  → типизированная domain-модель
  → Result<T>
  → Controller state
  → UI
```

В результате:

- экраны преимущественно отвечают за отображение;
- screens и widgets не вызывают API напрямую;
- основные данные представлены моделями, а не `dynamic`;
- ошибки не превращаются молча в `null` или пустые списки;
- pagination, refresh и retry тестируются без UI;
- API и storage можно подменять в тестах;
- большие экраны декомпозируются после выноса бизнес-логики;
- analyze, tests и Web build проверяются CI.

## 2. Не является целью

- полное одномоментное переписывание приложения;
- замена Provider на BLoC или Riverpod;
- обязательная замена `http` на Dio;
- использование Freezed и code generation;
- изменение UI одновременно с архитектурой;
- типизация всего reverse-engineered API одним коммитом;
- включение deployment-инфраструктуры в upstream PR.

Provider остаётся механизмом dependency injection и наблюдения за состоянием.

## 3. Целевая структура

```text
lib/
  core/
    api/
      api_client.dart
      http_api_client.dart
      app_failure.dart
      result.dart

  models/
    post.dart
    user.dart
    subsite.dart
    comment.dart
    reaction.dart
    channel.dart
    message.dart
    block.dart

  features/
    feed/
      data/
        feed_repository.dart
        dtf_feed_repository.dart
      models/
        feed_page.dart
        feed_type.dart
      presentation/
        feed_controller.dart
        feed_state.dart
        feed_screen.dart

    posts/
    comments/
    auth/
    profile/
    search/
    bookmarks/
    notifications/
    chat/
    editor/

  services/
    auth_service.dart
    preferences_service.dart
    current_user_service.dart
    notification_service.dart
```

Это модульный монолит внутри одного Flutter-приложения, а не набор отдельных packages.

## 4. Текущее состояние

В `refactor/architecture-foundation` уже сделано:

- исправлены analyzer lint;
- `flutter analyze --fatal-infos` проходит;
- создана тестовая инфраструктура;
- добавлены тесты `CommentTreeIndex` и `LinkifiedText`;
- добавлены `Result<T>` и типизированные `AppFailure`;
- создан подменяемый `ApiClient`;
- создан `HttpApiClient`;
- добавлены `Post`, `User`, `Subsite`, `PostCounters`, `PostReactions` и `ReactionCounter`;
- реализованы immutable collections и `copyWith`;
- добавлены тесты моделей и HTTP client;
- проходят 19 тестов.

Пока не сделано:

- модели не подключены к существующим экранам;
- Feed хранит состояние и вызывает `DtfApi`;
- `HttpApiClient` не подключён через Provider;
- Feed repository/controller не реализованы;
- CI не добавлен.

## 5. Этап 1 — завершить типизацию Post

На API boundary типизировать методы, возвращающие посты:

```dart
Future<Post?> getEntry(...);
Future<List<Post>> searchEntries(...);
Future<List<Post>> getDrafts(...);
Future<FeedPage> getSubsiteEntries(...);
```

Перевести на `Post`:

- `PostCard`;
- `PostScreen`;
- Feed;
- Search;
- Bookmarks;
- Drafts;
- UserProfile;
- Navigator arguments.

После миграции не должно остаться `dynamic post`, `post['title']` и мутаций post map.

Optimistic state обновлять через immutable copy:

```dart
_post = _post.copyWith(
  reactions: _post.reactions.toggle(reactionId),
);
```

При ошибке API восстанавливать предыдущую модель. `getTopComment` и комментарии временно остаются отдельным dynamic domain.

## 6. Этап 2 — Feed repository и controllers

### FeedRepository

```dart
abstract interface class FeedRepository {
  Future<Result<FeedPage>> loadPage({
    required FeedType type,
    FeedCursor? cursor,
  });
}
```

Repository отвечает за:

- API endpoints;
- pagination cursors;
- parsing;
- filtering;
- editorial timeline;
- преобразование ошибок.

### FeedController

Каждая вкладка (`popular`, `new`, `my`, `editorial`) получает отдельный controller.

Controller отвечает за:

- initial loading;
- refresh;
- pagination;
- retry;
- stale requests;
- duplicate `loadMore`;
- сохранение контента при ошибках.

### FeedState

```dart
class FeedState {
  final List<Post> posts;
  final List<Post> editorialPosts;
  final bool isInitialLoading;
  final bool isRefreshing;
  final bool isLoadingMore;
  final AppFailure? initialFailure;
  final AppFailure? paginationFailure;
}
```

После этапа `FeedScreen` не импортирует `DtfApi`.

## 7. Этап 3 — Dependency Injection

В `main.dart` предоставлять:

```text
SettingsService
http.Client
ApiClient
FeedRepository
```

Controllers создаются на уровне feature/widget и получают зависимости через constructor.

Не использовать:

- глобальный service locator;
- статические singleton repositories;
- скрытые зависимости внутри controller.

Все зависимости должны быть видны в конструкторах.

## 8. Этап 4 — обработка ошибок

Для мигрированных features запрещены пустые `catch`, `null` и пустой список как неявный признак ошибки.

Использовать:

- `NetworkFailure`;
- `TimeoutFailure`;
- `UnauthorizedFailure`;
- `ServerFailure`;
- `ParsingFailure`;
- `UnknownFailure`.

Поведение Feed:

- initial failure — сообщение и кнопка «Повторить»;
- pagination failure — старые посты остаются, retry показывается снизу;
- refresh failure — контент сохраняется, показывается SnackBar;
- «Моя лента» без авторизации — отдельное состояние без HTTP-запроса.

Автоматический бесконечный retry не добавлять.

## 9. Этап 5 — тесты и CI

Unit tests:

- parsing моделей;
- API error classification;
- repository paths и cursors;
- Feed controller;
- refresh и pagination;
- duplicate requests;
- stale responses;
- optimistic reaction rollback;
- secure-token migration.

Widget tests:

- Feed loading;
- Feed success;
- initial error;
- retry;
- pagination error;
- unauthenticated My Feed.

GitHub Actions на Ubuntu:

```bash
flutter pub get
flutter analyze --fatal-infos
flutter test
flutter build web --release
```

CI запускается для pull request и push в `main`.

## 10. Этап 6 — разделить SettingsService

Целевая декомпозиция:

```text
AuthService
PreferencesService
CurrentUserService
NotificationService
```

Ответственность:

- `AuthService` — token, login state, secure-storage migration;
- `PreferencesService` — theme, batch size, filters;
- `CurrentUserService` — ID, Plus и current-user state;
- `NotificationService` — unread count и polling state.

`SettingsService` временно остаётся facade, чтобы не мигрировать всё приложение одним diff.

## 11. Этап 7 — Posts и Comments

### Posts

Добавить:

```text
PostRepository
PostController
PostState
```

Controller управляет загрузкой поста, favorite, reactions и координацией comments loading.

### Comments

Добавить:

- типизированный `Comment`;
- `CommentsRepository`;
- `CommentsController`;
- collapse state;
- thread loading;
- optimistic reactions;
- comment add/edit.

`CommentTreeIndex` остаётся чистой тестируемой domain-логикой.

## 12. Этап 8 — остальные features

Мигрировать последовательно:

1. Search.
2. Bookmarks.
3. Profile/UserProfile.
4. Notifications.
5. Chat.
6. Editor.

Для каждого feature используется схема:

```text
models → repository → controller → UI → tests
```

Не создавать единый `AppController`, управляющий всем приложением.

## 13. Этап 9 — декомпозиция UI

После выноса бизнес-логики разделить крупные файлы:

- `post_screen.dart`;
- `comment_widget.dart`;
- `editor_screen.dart`;
- `dtf_api.dart`.

Выделять законченные компоненты:

- `PostHeader`;
- `PostBody`;
- `PostStats`;
- `CommentComposer`;
- `CommentList`;
- `AttachmentPicker`;
- `ReactionBar`.

Не дробить каждый `Container` в отдельный файл.

## 14. Стратегия веток и PR

Архитектурная работа делится на два последовательных PR.

### PR 1 — Architecture foundation

Текущая ветка:

```text
refactor/architecture-foundation
```

Этот PR содержит только уже реализованный фундамент:

- architecture design и implementation plan;
- исправление analyzer lint;
- базовую тестовую инфраструктуру;
- тесты comment tree и `LinkifiedText`;
- `Result<T>` и `AppFailure`;
- подменяемые `ApiClient` и `HttpApiClient`;
- начальные immutable-модели `Post`, `User`, `Subsite`, counters и reactions;
- unit tests API client и моделей;
- исправление Material ancestry для `ListTile`.

В PR 1 модели ещё не подключаются ко всем экранам, Feed не переносится в repository/controller, а `SettingsService` не разделяется. Его задача — добавить безопасный, компилируемый и протестированный фундамент для следующей ветки.

После merge PR #4 ветка переносится на актуальный `upstream/main`, проверяется и оформляется отдельным PR.

### PR 2 — Full application architecture migration

Следующая ветка создаётся от завершённой foundation-ветки:

```bash
git switch refactor/architecture-foundation
git switch -c refactor/application-architecture
```

Весь оставшийся roadmap реализуется в этой ветке и оформляется одним вторым PR. Этапы, которые раньше рассматривались как самостоятельные PR, становятся отдельными логическими коммитами.

### План коммитов PR 2

1. `refactor: migrate post consumers to typed models`
   - `DtfApi`, `PostCard`, `PostScreen`, Feed, Search, Bookmarks, Drafts и UserProfile.
2. `refactor: move Feed into repository and controllers`
   - Feed models, repository, отдельный controller каждой вкладки, error states и tests.
3. `refactor: wire application dependencies through Provider`
   - общий HTTP client, repositories и явный constructor injection.
4. `refactor: split authentication and preferences services`
   - `AuthService`, `PreferencesService`, `CurrentUserService`, `NotificationService`; временный `SettingsService` facade и migration tests.
5. `refactor: move Post into repository and controller`
   - загрузка поста, favorite, reactions и Post state.
6. `refactor: introduce typed Comments feature`
   - `Comment`, repository, controller, thread/collapse state и optimistic updates.
7. `refactor: migrate Search Bookmarks and Profile features`
   - repositories/controllers и удаление прямых API-вызовов из screens.
8. `refactor: migrate Notifications feature`
   - типизированная модель, repository/controller и unread state.
9. `refactor: migrate Chat and Editor features`
   - channel/message/editor models, repositories/controllers и write-error handling.
10. `refactor: decompose large screens and legacy API`
    - UI-компоненты, удаление оставшихся прямых `DtfApi` calls и разделение `dtf_api.dart`.
11. `test: add cross-feature regression coverage`
    - integration/widget tests критических пользовательских сценариев.
12. `ci: validate Flutter analysis tests and Web build`
    - GitHub Actions для pull requests и `main`.

Тесты каждого feature добавляются вместе с соответствующим feature-коммитом, чтобы история оставалась компилируемой. Отдельный regression commit проверяет взаимодействие уже мигрированных features.

PR 2 создаётся только после завершения полного roadmap и прохождения всех проверок. До merge PR 1 новая ветка может храниться в fork как stacked branch, но PR 2 против `main` не открывается.

После merge PR 1 собственные коммиты PR 2 переносятся на актуальный `upstream/main`:

```bash
git fetch upstream
git switch refactor/application-architecture
git rebase --onto upstream/main refactor/architecture-foundation
git push --force-with-lease origin refactor/application-architecture
```

Deployment-ветка `deploy/pwa-dev`, Firebase/CDT configuration и Cloudflare Worker не входят ни в PR 1, ни в PR 2.

## 15. Критерии итоговой готовности

Архитектурная миграция завершена, когда:

- screens не вызывают `DtfApi` напрямую;
- API полностью подменяется в тестах;
- основные сущности не используют `dynamic`;
- ошибки представлены типами;
- pagination и optimistic updates покрыты тестами;
- `SettingsService` разделён;
- новые features создаются через repository/controller;
- CI обязателен для merge;
- UI и пользовательское поведение не регрессировали;
- performance-изменения PR #4 сохранены.

## 16. Ближайший шаг

Завершить подготовку PR 1 из `refactor/architecture-foundation`: проверить состав файлов, привести локальную историю в reviewable вид после merge PR #4 и выполнить полный набор проверок.

Затем создать `refactor/application-architecture` от foundation-ветки. Первым коммитом PR 2 мигрировать `DtfApi` и все post consumers на уже созданную модель `Post`, сохраняя компилируемый проект после каждого вертикального среза.
