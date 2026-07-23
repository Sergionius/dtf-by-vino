# Project agent instructions

## Project

DTF by Vino is a Flutter client for the reverse-engineered DTF API. Supported targets include Android, iOS and Web/PWA.

Before architecture work, read:

- `docs/plans/2026-07-23-architecture-roadmap.md`
- `docs/plans/2026-07-22-feed-architecture-design.md`
- `docs/plans/2026-07-22-feed-architecture-implementation.md`

## Branches

- `feature/security-and-scroll` is the combined upstream PR branch.
- `refactor/architecture-foundation` is PR 1: quality checks, test infrastructure, API primitives and initial typed models.
- `refactor/application-architecture` is the future PR 2 branch created from `refactor/architecture-foundation`; it contains the full application migration.
- `deploy/pwa-dev` is deployment-only and must not be included in an upstream PR.
- Do not add full feature migrations to the foundation PR.
- Roadmap stages in PR 2 are separate logical commits, not separate PRs.
- After PR #4 merges, rebase PR 1 commits with:

  ```bash
  git rebase --onto upstream/main feature/security-and-scroll refactor/architecture-foundation
  ```

- After PR 1 merges, rebase PR 2 commits with:

  ```bash
  git rebase --onto upstream/main refactor/architecture-foundation refactor/application-architecture
  ```

- Do not create or update a PR unless explicitly requested.
- Do not push local changes unless explicitly requested.
- Never include local Firebase/CDT configuration in upstream commits.

## Local-only files

These are ignored through `.git/info/exclude` and must remain local:

- `cdt.yaml`
- `.cdt/`
- `.firebaserc`
- `firebase.json`

Do not modify `.gitignore` merely to publish these files.

## Architecture direction

Use this dependency flow for migrated features:

```text
UI → Controller/State → Repository → ApiClient → DTF API
```

Data returns as:

```text
JSON → parser/model → Result<T> → Controller state → UI
```

Rules:

- Keep Provider for dependency injection and observable state.
- Prefer constructor injection; do not add a service locator.
- Use manual immutable models with defensive `fromJson` parsing.
- Do not add Freezed, json_serializable or build_runner without approval.
- Use `Result<T>` and `AppFailure` in migrated features.
- Do not silently convert errors into `null`, empty lists or empty `catch` blocks.
- Screens should not call `DtfApi` directly after their feature is migrated.
- Migrate incrementally; the project must compile after each vertical slice.
- Preserve compatibility for features not migrated yet.

## Models and reverse-engineered API

The DTF API can change field type or nesting unexpectedly.

- Treat only truly required identifiers as mandatory.
- Use safe converters from `lib/util/json_safe.dart`.
- Unknown block types must degrade safely rather than break the entire post.
- Do not represent comments, notifications or messages as `Post` merely because they currently use maps.
- `Post` and other domain models remain immutable.
- Implement optimistic updates with `copyWith` and explicit rollback, not mutable JSON maps.
- Temporary `rawJson` compatibility access is allowed only while migrating old consumers. Do not use it in new feature code.

## Product behavior that must be preserved

- GIF autoplay remains enabled, including MP4-backed GIF without audio.
- Ordinary videos do not autoplay inline; they open on tap.
- iOS hosted video may use a downloaded local file.
- Do not remove or redesign `getTopComment` or the popular-comment block without explicit approval.
- Preserve comment collapse, lazy Sliver rendering and stable keys.
- Do not add media diagnostics or token logging to production code.

## Security

- Authentication tokens belong in `flutter_secure_storage` on supported secure platforms.
- Never print, log, persist in fixtures, or send `X-Device-Token` to unapproved services.
- Preserve safe migration ordering: write secure storage successfully before deleting the legacy token.
- Web fallback behavior over insecure HTTP must remain explicit.
- Avoid broad network security exceptions. Any `NSAllowsArbitraryLoads` change requires explicit review.

## Web deployment

Web deployment infrastructure is intentionally separate from upstream architecture work.

- The Cloudflare Worker proxies only the public editorial endpoint that lacks Firebase-origin CORS:

  ```text
  GET /v2.31/search/posts?editorial=true
  ```

- Do not route all DTF traffic through the Worker.
- Native apps and other API endpoints connect directly to `https://api.dtf.ru`.
- The Worker source lives outside this repository at:

  ```text
  /Users/sergiomalkin/Developer/dtf-api-proxy
  ```

- `cdt run firebase-deploy` is a real production Firebase Hosting deployment. Run it only after explicit confirmation.

## Code style

- Follow `flutter_lints` and keep `flutter analyze --fatal-infos` clean.
- Format only changed/new Dart files. Avoid formatting large unrelated legacy files.
- Keep one logical roadmap stage per commit and include that stage's tests in the same commit.
- Before opening the single architecture PR, use interactive rebase to remove temporary/fixup commits and align history with the roadmap.
- Do not add dependencies when a small local implementation is sufficient.
- Do not make unrelated UI changes during architecture migration.

## Required checks

During implementation run focused tests first. Before considering a branch ready, run:

```bash
flutter pub get
flutter analyze --fatal-infos --no-pub
flutter test
flutter build web --release
flutter build ios --simulator --no-codesign
git diff --check
```

If a platform build is intentionally skipped, state that explicitly.

## Current architecture progress

Already implemented on `refactor/architecture-foundation`:

- analyzer cleanup;
- baseline tests for comment flattening and `LinkifiedText`;
- `AppFailure` and `Result<T>`;
- injectable `ApiClient` and `HttpApiClient`;
- immutable `Post`, `User`, `Subsite`, counters and reactions models;
- model/client tests;
- Material ancestry fix for `ListTile` card surfaces.

Next steps:

1. finish and validate PR 1 from `refactor/architecture-foundation` after PR #4 merges;
2. create `refactor/application-architecture` from the completed foundation branch;
3. migrate DTF post-returning methods and all post consumers to `Post` in PR 2;
4. continue the full migration according to `docs/plans/2026-07-23-architecture-roadmap.md`.
