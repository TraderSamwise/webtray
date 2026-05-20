# WebTray

A lightweight macOS menu bar app that wraps web apps (iCloud Notes, Gmail, Google Calendar) in a popover. Click the status bar icon to instantly access your apps without switching contexts.

## Features

- **Menu bar popover** — click to open, click away to dismiss
- **Three tabs** — iCloud Notes, Gmail, Google Calendar with instant switching
- **Lazy loading** — tabs only create WebViews when first visited
- **Idle teardown** — background tabs free memory after 10 minutes of inactivity
- **Cookie persistence** — stay logged in across restarts
- **External links** — opens non-Google/Apple links in your default browser
- **No Dock icon** — runs as a pure menu bar accessory

## Install

```bash
swift build -c release
cp .build/release/webtray ~/.local/bin/
```

## Usage

```bash
webtray
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--url` | `https://www.icloud.com/notes` | URL for the first tab |
| `--icon` | `checklist` | SF Symbol name for the status bar icon |
| `--title` | `WebTray` | App title (shown in right-click menu) |
| `--idle` | `600` | Seconds before idle tabs are torn down |
| `--size` | `630x700` | Popover dimensions (`WxH`) |

### Auto-start at login

Create a LaunchAgent at `~/Library/LaunchAgents/com.webtray.app.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.webtray.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/webtray</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

Then load it:

```bash
launchctl load ~/Library/LaunchAgents/com.webtray.app.plist
```

## Requirements

- macOS 13+
- Swift 5.9+

## License

MIT
