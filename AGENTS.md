# Repository Guidelines

## Project Structure & Module Organization
`lib/` contains the Flutter app entrypoint and feature code, with shared UI in `lib/src/widgets/`, theme setup in `lib/src/theme/`, domain models in `lib/src/models/`, and platform/runtime coordination in `lib/src/services/`. Tests live in `test/` and currently follow the app config flow. Bundled runtime assets, helper scripts, and reference configs are under `assets/runtime/`. Linux runner files are in `linux/`, packaging templates in `packaging/`, and release helpers in `scripts/` plus `build-linux.sh`.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes. Use `flutter analyze` for static checks and `flutter test` for the test suite. Build the Linux app with `./build-linux.sh`; the runnable bundle is created at `build/linux/x64/release/bundle/`. Create a Debian package with `./scripts/package-deb.sh`. Build the full release set, including source and portable archives, with `./scripts/build-release-artifacts.sh`, which writes artifacts to `dist/`.

## Coding Style & Naming Conventions
Follow `flutter_lints` from `analysis_options.yaml`. Use 2-space indentation and standard Dart formatting via `dart format .` or `flutter format .` before review. Keep filenames `snake_case.dart`, classes and enums `UpperCamelCase`, and methods, variables, and test descriptions in clear lower camel case. Keep widgets small and move service or process-control logic into `lib/src/services/`.

## Testing Guidelines
Add or update `flutter_test` coverage for behavior changes. Place tests in `test/` with names ending in `_test.dart`; mirror the source area when practical, for example `test/app_config_test.dart`. Prefer focused unit tests for models and services, and add widget tests when UI state or rendering changes. Run `flutter test` locally before opening a PR.

## Commit & Pull Request Guidelines
The visible history only contains `Initial commit`, so there is no mature convention to copy yet. Use short, imperative commit subjects such as `Add runtime config validation` and keep unrelated changes separate. PRs should explain the user-visible change, list verification steps (`flutter analyze`, `flutter test`, packaging checks if relevant), and include screenshots for UI changes. Link related issues or release tasks when applicable.

## Release & Packaging Notes
Versioning is driven by `pubspec.yaml`, and the GitHub workflow in `.github/workflows/release-linux.yml` publishes artifacts for tags matching `v*`. If you change packaging behavior, verify both `packaging/arch/` and `packaging/rpm/` templates still match the generated release archives.
