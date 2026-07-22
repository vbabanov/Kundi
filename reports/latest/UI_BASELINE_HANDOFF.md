# UI Baseline Handoff

- Accepted baseline commit: `42cc7b6`
- Tag: `ui-initial-design-baseline`

Accepted pages:
- `Оценки -> Главная`
- `Оценки -> За неделю`
- `Оценки -> Итоговые`
- `ДЗ / Тема урока`
- `bottom nav`
- `страница логина`
- `страницы профиля`

Baseline files:
- `mobile/assets/images/load_mascot.webp`
- `mobile/assets/images/logo.webp`
- `mobile/lib/features/auth/presentation/auth_page.dart`
- `mobile/lib/features/auth/presentation/main_shell_page.dart`
- `mobile/lib/features/homework/presentation/homework_page.dart`
- `mobile/lib/features/profile/presentation/profile_page.dart`
- `mobile/test/widget/features/auth/main_shell_page_contract_test.dart`
- `mobile/test/widget/features/homework/homework_page_contract_test.dart`
- `mobile/test/widget/features/profile/profile_page_v2_sections_test.dart`

Latest screenshots:
- `reports/latest/login.png`
- `reports/latest/profile.png`
- `reports/latest/grades_main.png`
- `reports/latest/grades_week.png`
- `reports/latest/grades_totals.png`
- `reports/latest/homework_dz.png`
- `reports/latest/homework_topic.png`
- `reports/latest/bottom_nav.png`

Archived reports:
- old `reports/ui_reference_*`
- old `reports/ui_reference_week_*`
- old `reports/ui_reference_week_table_*`
- old `reports/live_run/*`

Intentional dirty files left out of baseline:
- `mobile/assets/icon.png` left dirty and excluded from stage/commit

Worktrees and copies:
- kept `C:\Users\baban\.codex\worktrees\8a8e\Kundi` because it is dirty; patch/status saved to `D:\Kundi_cleanup_backup\20260708_1845`
- kept `C:\Users\baban\.codex\worktrees\f998\Kundi` because ownership is ambiguous from current user context
- nearby old copies were inventoried only; no blind deletion was done

Test commands and results:
- `flutter analyze` -> warnings outside UI baseline scope; no cleanup-wide blocking error fixed here
- `flutter test` -> full suite still has unrelated legacy failures outside accepted baseline scope
- `flutter test test/widget/features/auth/main_shell_page_contract_test.dart` -> passed
- `flutter test test/widget/features/homework/homework_page_contract_test.dart` -> passed
- `flutter test test/widget/features/profile/profile_page_v2_sections_test.dart` -> passed
- `flutter test test/widget/features/grades/grades_page_v2_test.dart test/unit/features/grades/grades_controller_v2_test.dart test/unit/features/grades/grades_repository_v2_test.dart` -> passed
- `flutter build apk --debug --dart-define=USE_TYPED_V2_READ=true --dart-define=ENABLE_V2_PARITY_SHADOW=true` -> failed in this environment because `sqlite3` native asset download timed out

Current APK:
- `mobile/build/app/outputs/flutter-apk/app-debug.apk`

Do not touch in next UI-pass:
- `mobile/assets/icon.png` unless product explicitly accepts the new icon
- backend/API/contracts/runtime code for visual cleanup only
- archived report folders unless replacing them with a new accepted baseline

## Stable tested checkpoint

- Stable tested commit: `97b19bc`
- Intended tag: `mobile-ui-stable-tested`
- Tag creation status: blocked in Codex Windows terminal by `CryptUnprotectData failed: 2148073483`
- Manual command:
  ```powershell
  cd D:\Kundi
  git status --short
  git tag mobile-ui-stable-tested 97b19bc
  git tag --list | findstr mobile-ui-stable-tested
  ```

## Accepted Home dashboard checkpoint

- Home commit: `01f747f` (`feat(home): add Kundi dashboard and weekly gamification`)
- Main page now includes the Kundi hero, greeting, and Kundi action row.
- Gamification summary shows `ДЗ сегодня`, `ДЗ за неделю`, and `Посещаемость`.
- Verification after the Home commit: `flutter test` PASS (155 tests); debug APK build PASS with `USE_TYPED_V2_READ=true` and `ENABLE_V2_PARITY_SHADOW=true`.
- The intended `mobile-ui-stable-tested` tag is still not created because the Codex Windows terminal is blocked by `CryptUnprotectData failed: 2148073483`.
