# NZapret Desktop

Flutter-приложение для Linux поверх bundled `nfqws`-стратегии с управлением через `nftables`.

## Что входит в релиз

- `.deb` для Debian/Ubuntu-подобных систем
- portable `tar.gz` с уже собранным Linux bundle
- source `tar.gz` для ручной сборки на Arch, Fedora, openSUSE и других дистрибутивах
- шаблоны `PKGBUILD` и `rpm .spec`

## Подготовка к сборке

Для ручной сборки нужен установленный Flutter SDK с поддержкой Linux desktop. Установите Flutter удобным для вас способом, затем проверьте toolchain:

```bash
flutter config --enable-linux-desktop
flutter doctor -v
```

После этого поставьте системные зависимости.

<details>
<summary>Arch-based</summary>

```bash
sudo pacman -Syu --needed git clang cmake gtk3 ninja nftables pkgconf polkit util-linux-libs
```

</details>

<details>
<summary>Fedora-based</summary>

```bash
sudo dnf install git clang cmake gtk3-devel libblkid ninja-build nftables pkgconf-pkg-config polkit
```

</details>

<details>
<summary>Debian-based</summary>

```bash
sudo apt-get update
sudo apt-get install -y git clang cmake libblkid1 libgtk-3-dev libstdc++-12-dev nftables ninja-build pkg-config policykit-1
```

</details>

Что здесь важно:

- `nftables` нужен самому приложению во время работы.
- `polkit` и `pkexec` нужны для privileged start/stop из UI без запуска приложения целиком от `root`.
- пакет с `libblkid` нужен потому, что bundled `libflutter_linux_gtk.so` линкуется с `libblkid.so.1`.

## Простая сборка и установка приложения

1. Склонируйте репозиторий и зайдите в него.

```bash
git clone <repo-url>
cd QNZapret
```

2. Подтяните Dart/Flutter-зависимости проекта.

```bash
flutter pub get
```

3. Соберите release bundle.

```bash
./build-linux.sh
```

Готовый bundle появится здесь:

```bash
build/linux/x64/release/bundle/
```

4. Установите приложение как обычное desktop-приложение в `/opt`, добавьте launcher и иконку.

```bash
sudo install -d /opt/nzapret-desktop
sudo cp -R build/linux/x64/release/bundle/. /opt/nzapret-desktop/
sudo ln -sf /opt/nzapret-desktop/nzapret_desktop /usr/bin/nzapret-desktop
sudo install -Dm644 packaging/linux/nzapret-desktop.desktop /usr/share/applications/nzapret-desktop.desktop
sudo install -Dm644 assets/branding/nzapret-desktop.svg /usr/share/icons/hicolor/scalable/apps/nzapret-desktop.svg
```

5. Запустите приложение из меню приложений или командой:

```bash
nzapret-desktop
```

## Локальная сборка release

```bash
flutter pub get
./build-linux.sh
```

Готовый bundle появится здесь:

```bash
build/linux/x64/release/bundle/
```

Запуск без установки:

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
