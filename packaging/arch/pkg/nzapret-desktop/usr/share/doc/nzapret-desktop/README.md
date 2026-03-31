# NZapret Desktop

Flutter-приложение для Linux поверх bundled `nfqws`-стратегии с управлением через `nftables`.

## Что входит в релиз

- `.deb` для Debian/Ubuntu-подобных систем
- portable `tar.gz` с уже собранным Linux bundle
- source `tar.gz` для ручной сборки на Arch, Fedora, openSUSE и других дистрибутивах
- шаблоны `PKGBUILD` и `rpm .spec`

## Локальная сборка release

```bash
flutter pub get
./build-linux.sh
```

Готовый bundle появится здесь:

```bash
build/linux/x64/release/bundle/
```

Запуск:

```bash
./build/linux/x64/release/bundle/nzapret_desktop
```

## Сборка .deb

```bash
./scripts/package-deb.sh
```

Результат:

```bash
dist/nzapret-desktop_<version>_<arch>.deb
```

Пакет ставит приложение в `/opt/nzapret-desktop`, добавляет launcher в `/usr/bin/nzapret-desktop` и `.desktop`-ярлык в меню приложений.

## Полный набор release-артефактов

```bash
./scripts/build-release-artifacts.sh
```

Команда соберёт:

- `.deb`
- portable `tar.gz`
- source `tar.gz`

в директорию `dist/`.

## Ручная сборка из исходников

Нужны:

- Flutter SDK
- `cmake`
- `ninja`
- `clang`
- `pkg-config`
- dev-пакеты GTK 3
- dev-пакеты `libblkid`
- `nftables`
- `pkexec`/polkit для privileged start/stop из UI

После установки зависимостей сборка одинаковая почти везде:

```bash
flutter pub get
./build-linux.sh
```

Это удобный путь для Arch и rpm-дистрибутивов: на GitHub можно брать либо исходники релиза, либо portable `tar.gz`, если не хочется собирать пакетную обвязку.

## PKGBUILD и rpm spec

В репозитории есть готовые шаблоны:

- `packaging/arch/PKGBUILD`
- `packaging/rpm/nzapret-desktop.spec`

Оба шаблона по умолчанию ожидают source-архив релиза вида:

```bash
dist/nzapret-desktop-<version>-source.tar.gz
```

Для GitHub Releases можно оставить URL на release asset, а для локальной проверки передать свой путь:

```bash
SOURCE_URL=file:///absolute/path/to/nzapret-desktop-1.0.0+1-source.tar.gz makepkg -si
```

```bash
rpmbuild -ba packaging/rpm/nzapret-desktop.spec \
  --define "source_url file:///absolute/path/to/nzapret-desktop-1.0.0+1-source.tar.gz"
```

## Как лучше релизить на GitHub

Практичный вариант:

1. Вести версии через `pubspec.yaml`.
2. Создавать git-теги вида `v1.0.0`.
3. Пушить тег в GitHub.
4. GitHub Actions из `.github/workflows/release-linux.yml` соберёт:
   - `.deb`
   - portable `tar.gz`
   - source `tar.gz`
   - workflow artifact
   - assets для GitHub Release

Итоговая схема по дистрибутивам:

- Debian/Ubuntu: ставят `.deb`
- Arch/Fedora/openSUSE: либо собирают из исходников по README, либо берут portable `tar.gz`

Если позже захочешь нативное распространение по экосистемам, логичный следующий шаг:

- AUR для Arch
- COPR для Fedora
- OBS/Open Build Service для openSUSE
- отдельный `.rpm` через `rpmbuild` или `fpm`
