#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
./scripts/swift-tool.sh build -c release
task_bin="$(./scripts/swift-tool.sh build -c release --show-bin-path)"
task_app="$task_root/dist/SSH Monitor.app"
mkdir -p "$task_app/Contents/MacOS"
cp "$task_bin/SSHMonitor" "$task_app/Contents/MacOS/SSHMonitor"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
codesign --force --deep --sign - "$task_app"
printf 'Built: %s\n' "$task_app"

if [[ "${1:-}" == "--install" ]]; then
  task_install="$HOME/Applications/SSH Monitor.app"
  task_agent="$HOME/Library/LaunchAgents/app.sshmonitor.menubar.plist"
  task_domain="gui/$(id -u)"
  launchctl bootout "$task_domain/app.sshmonitor.menubar" 2>/dev/null || true
  pkill -x SSHMonitor 2>/dev/null || true
  mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
  rm -rf "$task_install"
  ditto "$task_app" "$task_install"
  cat > "$task_agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>app.sshmonitor.menubar</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$task_install</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
  plutil -lint "$task_agent"
  launchctl bootstrap "$task_domain" "$task_agent"
  printf 'Installed: %s\n' "$task_install"
fi
