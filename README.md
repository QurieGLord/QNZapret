# 🛡️ NZapret Desktop

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://linux.org)

**NZapret Desktop** — это современный графический контроллер для Linux, работающий поверх bundled-стратегии `nfqws` (из состава проекта `zapret`). Управление правилами фильтрации трафика осуществляется через `nftables`.

---

## ✨ Основные возможности

- 🚀 **Быстрый старт**: Запуск и остановка стратегии обхода в один клик.
- 🛠️ **Управление через pkexec**: Безопасное выполнение привилегированных действий без запуска всего GUI от root.
- 📦 **Всё включено**: Бинарный файл `nfqws` и вспомогательные скрипты уже в комплекте.
- 🎨 **Современный UI**: Чистый интерфейс на Flutter с поддержкой темных и светлых тем.

---

## 🛠️ Подготовка и установка зависимостей

Перед сборкой убедитесь, что в вашей системе установлены все необходимые инструменты.

### 🐧 Arch Linux
```bash
# 1. Системные зависимости
sudo pacman -Syu --needed git clang cmake gtk3 ninja nftables pkgconf polkit util-linux-libs

# 2. Установка Flutter (рекомендуется через AUR или вручную)
# Через AUR (например, yay):
yay -S flutter
# Или вручную в ~/dev/flutter и добавление в PATH
```

### 📦 Fedora
```bash
# 1. Системные зависимости
sudo dnf install git clang cmake gtk3-devel libblkid ninja-build nftables pkgconf-pkg-config polkit

# 2. Установка Flutter (рекомендуется ручная установка)
# Скачайте архив с сайта flutter.dev, распакуйте и добавьте в PATH.
```

### 🍎 Debian / Ubuntu / Mint
```bash
# 1. Системные зависимости
sudo apt-get update
sudo apt-get install -y git clang cmake libblkid1 libgtk-3-dev libstdc++-12-dev nftables ninja-build pkg-config policykit-1

# 2. Установка Flutter
# Самый простой способ через snap:
sudo snap install flutter --classic
# Или ручная установка по инструкции с официального сайта.
```

> 💡 **Важно**: После установки Flutter обязательно выполните:
> ```bash
> flutter config --enable-linux-desktop
> flutter doctor  # Убедитесь, что Linux toolchain отмечен галочкой [✓]
> ```

---

## 🚀 Сборка и установка

Если вы скачали исходный код, выполните следующие шаги для установки приложения в систему:

### 1. Подготовка Dart-пакетов
```bash
flutter pub get
```

### 2. Компиляция Release-билда
```bash
./build-linux.sh
```

### 3. Установка в систему (в `/opt`)
```bash
# Создаем директорию и копируем файлы
sudo install -d /opt/nzapret-desktop
sudo cp -R build/linux/x64/release/bundle/. /opt/nzapret-desktop/

# Создаем символьную ссылку для запуска из терминала
sudo ln -sf /opt/nzapret-desktop/nzapret_desktop /usr/bin/nzapret-desktop

# Устанавливаем ярлык и иконку
sudo install -Dm644 packaging/linux/nzapret-desktop.desktop /usr/share/applications/nzapret-desktop.desktop
sudo install -Dm644 assets/branding/nzapret-desktop.svg /usr/share/icons/hicolor/scalable/apps/nzapret-desktop.svg

# Важно: устанавливаем права на исполнение для внутренних скриптов
sudo chmod +x /opt/nzapret-desktop/data/flutter_assets/assets/runtime/bin/nfqws
sudo chmod +x /opt/nzapret-desktop/data/flutter_assets/assets/runtime/scripts/nzapret-helper.sh
```

---

## 📦 Пакетные менеджеры (Alternative)

В репозитории доступны шаблоны для сборки нативных пакетов:
- **Debian**: `./scripts/package-deb.sh`
- **Arch**: `packaging/arch/PKGBUILD`
- **Fedora/RPM**: `packaging/rpm/nzapret-desktop.spec`

---

## 🤝 Благодарности

- Проекту [zapret](https://github.com/bol-van/zapret) за бинарный файл `nfqws` и логику обхода.
- Сообществу Flutter за отличный фреймворк.
