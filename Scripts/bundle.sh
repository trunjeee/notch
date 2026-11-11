#!/bin/bash
# Builds notchbytrj.app without Xcode: SwiftPM produces the binary, this script
# assembles the bundle around it and ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Notch by trj.app"
VERSION="$(sed -n 's/^VERSION=//p' "$ROOT/Scripts/version" 2>/dev/null || echo 0.1.0)"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/notchbytrj"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/notchbytrj"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Notch by trj</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ru</string></array>
    <key>CFBundleDisplayName</key><string>Notch by trj</string>
    <key>CFBundleIdentifier</key><string>com.notchbytrj.app</string>
    <key>CFBundleExecutable</key><string>notchbytrj</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Notch by trj читает название текущего трека и управляет воспроизведением в Apple Music и Spotify.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Notch by trj показывает ближайшие встречи и кнопку подключения к ним.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Notch by trj показывает ближайшие встречи и кнопку подключения к ним.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Notch by trj показывает подключённые Bluetooth-устройства и их заряд.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Notch by trj показывает и отмечает выполненными твои напоминания.</string>
    <key>NSRemindersUsageDescription</key>
    <string>Notch by trj показывает и отмечает выполненными твои напоминания.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Notch by trj превращает речь в текст, пока удерживается правый Option.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Notch by trj распознаёт речь локально на этом Mac, чтобы вставлять текст в любое поле ввода.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -f "$ROOT/Resources/StatusIcon.pdf" ]; then
    cp "$ROOT/Resources/StatusIcon.pdf" "$APP/Contents/Resources/StatusIcon.pdf"
fi

for ext in mp3 wav aiff m4a; do
    if [ -f "$ROOT/Resources/SwitchSound.$ext" ]; then
        cp "$ROOT/Resources/SwitchSound.$ext" "$APP/Contents/Resources/SwitchSound.$ext"
    fi
done

# Таблицы строк кладутся прямо в бандл, а не через ресурсы SwiftPM: бандл здесь
# собирается вручную, и .lproj рядом с исполняемым файлом — то, где их ищет сама
# macOS. Язык она выбирает потом сама, по списку предпочитаемых у пользователя.
echo "==> локализации"
for lproj in "$ROOT"/Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$APP/Contents/Resources/"
    echo "    $(basename "$lproj")"
done

# Now Playing helper. Built here rather than by SwiftPM because it is not linked
# into the app: it is loaded into /usr/bin/perl at runtime. See helper.m.
echo "==> building Now Playing helper"
clang -dynamiclib -fobjc-arc -O2 \
    -mmacosx-version-min=15.0 \
    -framework Foundation \
    -o "$APP/Contents/Resources/libnotchbytrjmedia.dylib" \
    "$ROOT/Sources/notchbytrjMediaHelper/helper.m"

# Расширенные атрибуты снимаются первыми. iCloud вешает на файлы
# com.apple.FinderInfo, а codesign отказывается подписывать что-либо с ним —
# «resource fork, Finder information, or similar detritus not allowed». Папка
# «Рабочий стол» синхронизируется с iCloud у многих по умолчанию, так что клон
# репозитория там перестает подписываться, стоило его туда перенести.
xattr -cr "$APP"

echo "==> signing"
# Подписываем стабильным self-signed сертификатом, а не ad-hoc: macOS
# привязывает разрешения TCC (Accessibility, Input Monitoring, микрофон и
# прочие) к designated requirement. Ad-hoc подпись сводит его к хэшу
# бинарника, который меняется каждую сборку, — и macOS видит «новое
# приложение», переспрашивая все разрешения. С сертификатом requirement —
# «bundle id + сертификат», он переживает любые пересборки. Сертификат
# создается один раз: Scripts/setup-signing.sh
SIGN_IDENTITY="${SIGN_IDENTITY:-trj-dev}"
if security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
    codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP" || {
        echo "!!! codesign не смог подписать бандл — см. вывод выше" >&2
        exit 1
    }
else
    # Ошибка не глушится и не понижается до предупреждения. Раньше отказ печатал
    # мягкую строку и возвращал ноль: скрипт доходил до «done», а в build лежал
    # бандл, про который codesign говорит «code object is not signed at all».
    # Заметить это можно было только по возвращающимся запросам TCC — то есть у
    # того, кто уже поставил приложение.
    echo "    identity '$SIGN_IDENTITY' не найден — подписываю ad-hoc"
    echo "    (разрешения будут слетать каждую сборку; создай сертификат: Scripts/setup-signing.sh)"
    codesign --force --deep --sign - "$APP" || {
        echo "!!! codesign не смог подписать бандл — см. вывод выше" >&2
        exit 1
    }
fi
codesign --verify --strict "$APP" || {
    echo "!!! подпись не прошла проверку" >&2
    exit 1
}

echo "==> done: $APP"
