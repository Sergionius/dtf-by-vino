# Оптимизация скролла ленты и комментариев

## GitHub Issue

### Проблема

Лента и комментарии заметно теряют плавность во время скролла, особенно в Web и iOS PWA. Проблема сохраняется после загрузки данных и возврата на уже открытый экран, поэтому не ограничивается скоростью сети.

### Обнаруженные причины

1. `SliverList` лениво создаёт только корневые комментарии, но каждый корень рекурсивно строит всю ветку через `Column`.
2. `_loadedDescendants` повторно обходит потомков для каждого узла и может давать близкую к O(n²) сложность.
3. Реакции в ленте и комментариях анимированы постоянно.
4. GIF и silent video автоматически воспроизводятся прямо в ленте.
5. `PostCard.initState()` может запускать отдельный запрос популярного комментария для каждой карточки.
6. `LinkifiedText` повторно выполняет HTML/URL parsing и накапливает `TapGestureRecognizer`.
7. Дерево комментариев пересоздаётся при каждом build экрана поста.

### Предлагаемые изменения

- Использовать статичные реакции в scrollable-контенте.
- Не запускать GIF и видео автоматически в ленте.
- Преобразовывать дерево комментариев в плоский список видимых строк.
- Сделать каждый комментарий отдельным элементом `SliverList`.
- Убрать рекурсивный `_loadedDescendants`.
- Кешировать структуру комментариев.
- Исправить lifecycle `TapGestureRecognizer`.
- Убрать сетевые запросы из `PostCard.initState`.
- Добавить стабильные ключи по ID.
- Сравнить profile-метрики до и после.

### Ожидаемый результат

- Sliver действительно лениво создаёт отдельные комментарии;
- во время скролла не запускаются дополнительные HTTP-запросы;
- feed не содержит автоматически воспроизводимых видео;
- количество пропущенных кадров существенно снижается;
- потребление памяти не растёт после повторных rebuild комментариев.

---

## Implementation plan

### Этап 0. Зафиксировать baseline

Проверять не в debug, а в profile/release:

```bash
flutter run -d chrome --profile
```

Сценарии:

1. Лента минимум из 40–50 постов.
2. Пост минимум с 200 комментариями.
3. Быстрый скролл вниз и обратно.
4. Открытие поста и возврат в ленту.
5. Повторение на том же устройстве и браузере.

Сохранить:

- timeline Flutter DevTools;
- число медленных кадров;
- максимальное время build/raster;
- потребление памяти;
- число запросов при скролле.

### Этап 1. Быстрые улучшения

Отдельный PR с минимальным риском.

#### Статичные реакции

В `PostCard` и `CommentWidget`:

```dart
ReactionIcon(
  id: reactionId,
  animated: false,
)
```

Анимацию оставить в picker и пользовательском feedback.

#### Стабильные ключи

```dart
PostCard(
  key: ValueKey(post['id']),
)

CommentWidget(
  key: ValueKey(comment['id']),
)
```

#### Убрать лишние запросы

Не вызывать `getTopComment` из `PostCard.initState`.

Возможные дальнейшие варианты:

- убрать preview популярного комментария;
- загрузить данные заранее на уровне feed repository;
- запускать загрузку после остановки скролла;
- ограничить concurrency.

### Этап 2. Облегчённый MediaView для ленты

Добавить режим:

```dart
enum MediaPlaybackPolicy {
  posterOnly,
  onTap,
  autoplay,
}
```

Для ленты:

```dart
MediaView(
  media: media,
  playbackPolicy: MediaPlaybackPolicy.posterOnly,
)
```

Поведение:

- изображение — уменьшенный preview;
- GIF — статичный poster и badge `GIF`;
- video — poster и кнопка Play;
- `VideoPlayerController` в feed не создаётся;
- воспроизведение начинается только после открытия.

На экране поста autoplay также лучше отключить до нажатия или появления в viewport.

### Этап 3. Исправить LinkifiedText

Сейчас recognizer’ы добавляются при каждом `build`.

Нужно:

1. Парсить входной HTML в `initState`.
2. Перепарсивать только в `didUpdateWidget`, если изменился текст.
3. Перед перепарсингом освобождать старые recognizer’ы.
4. В `dispose` освобождать оставшиеся.
5. Не запускать RegExp parsing при каждом UI rebuild.

Добавить тест, подтверждающий отсутствие повторного накопления spans/recognizer’ов.

### Этап 4. Плоская модель комментариев

Добавить представление:

```dart
class VisibleComment {
  final dynamic comment;
  final int depth;
  final int descendantCount;
}
```

Функция преобразования:

```dart
List<VisibleComment> flattenComments(
  List<dynamic> comments,
  Set<int> collapsedIds,
);
```

Она должна:

- построить `childrenByParent` один раз;
- один раз рассчитать число потомков;
- вернуть только видимые строки;
- учитывать свёрнутые ветки;
- сохранять исходный порядок.

После этого использовать:

```dart
SliverList.builder(
  itemCount: visibleComments.length,
  itemBuilder: (_, index) {
    final row = visibleComments[index];
    return CommentWidget(
      key: ValueKey(row.comment['id']),
      comment: row.comment,
      depth: row.depth,
    );
  },
)
```

Убрать recursive `CommentNode` и `_loadedDescendants`.

### Этап 5. Кеширование derived state

Пересчитывать comment tree только когда изменились:

- `_comments`;
- collapsed IDs;
- загруженная ветка.

Не выполнять внутри каждого `build`:

```dart
CommentThread.buildTree(_comments);
```

Также заранее вычислять:

- распарсенные блоки поста;
- отсортированные реакции;
- очищенный preview text;
- параметры media.

### Этап 6. Изоляция перерисовок

После основных исправлений проверить DevTools Repaint Rainbow.

Только по результатам профилирования добавлять:

```dart
RepaintBoundary(
  child: CommentWidget(...),
)
```

Не оборачивать всё подряд: `SliverChildBuilderDelegate` уже создаёт repaint boundaries для верхнеуровневых элементов. После flatten каждый комментарий естественным образом получит отдельную границу.

### Этап 7. Проверка результата

Повторить baseline на том же устройстве и браузере.

## Критерии готовности

Функциональные:

- каждый видимый комментарий является отдельным Sliver child;
- collapsed branch не создаёт дочерние widget’ы;
- в feed не создаются `VideoPlayerController`;
- GIF в feed не анимируются автоматически;
- реакции в feed/comments статичны;
- скролл не запускает `getTopComment`;
- `LinkifiedText` не накапливает recognizer’ы.

Производительность:

- количество медленных кадров снижено минимум на 50% относительно baseline;
- память не растёт после нескольких циклов скролла вниз/вверх;
- возврат из поста не запускает повторную загрузку ленты;
- визуальное поведение и действия с комментариями не изменились.

## Предлагаемое разбиение на PR

1. Статичные реакции, keys и удаление per-card запросов.
2. Poster-only media в feed.
3. Исправление `LinkifiedText`.
4. Flatten comment tree и настоящий lazy Sliver.
5. Memoization и финальное профилирование.
