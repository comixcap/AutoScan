#!/bin/bash
# Собирает AutoScan.app — обычное приложение macOS, запускается двойным кликом.
#
#   ./build_app.sh              релиз (по умолчанию)
#   ./build_app.sh debug        отладочная сборка
set -e

cd "$(dirname "$0")"
CONFIG="${1:-release}"
APP="AutoScan.app"

echo "==> Сборка ($CONFIG)"
swift build -c "$CONFIG"

BIN=$(swift build -c "$CONFIG" --show-bin-path)/AutoScan
if [ ! -f "$BIN" ]; then
    echo "Не найден бинарник: $BIN" >&2
    exit 1
fi

echo "==> Сборка бандла"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AutoScan"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>AutoScan</string>
    <key>CFBundleDisplayName</key>           <string>AutoScan</string>
    <key>CFBundleIdentifier</key>            <string>local.autoscan.app</string>
    <key>CFBundleExecutable</key>            <string>AutoScan</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>1.0</string>
    <key>CFBundleVersion</key>               <string>1</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <!-- нужно для поиска BLE-адаптеров OBD -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Поиск и подключение Bluetooth-адаптера OBD-II для чтения данных автомобиля.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Подключение к Bluetooth-адаптеру OBD-II.</string>
    <!-- Wi-Fi-донглы работают по локальной сети -->
    <key>NSLocalNetworkUsageDescription</key>
    <string>Связь с Wi-Fi-адаптером OBD-II в локальной сети автомобиля.</string>
</dict>
</plist>
PLIST

# подпись «для себя» — иначе macOS не даст приложению доступ к Bluetooth
echo "==> Подпись"
codesign --force --deep --sign - "$APP" 2>/dev/null \
    && echo "    подписано ad-hoc" \
    || echo "    подпись не выполнена (приложение всё равно запустится)"

echo
echo "Готово: $(pwd)/$APP"
echo "Запуск:            open $APP"
echo "Самопроверка:      $APP/Contents/MacOS/AutoScan --selftest tcp:127.0.0.1:35000"
