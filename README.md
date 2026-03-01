# UsageBar

A macOS menu bar app that tracks your AI usage limits in real-time.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Menu bar native** — lives in your macOS status bar, always accessible
- **Track multiple services** — Claude, Codex, Cursor, Gemini, Copilot
- **Daily & weekly limits** — set custom thresholds per service
- **Countdown timers** — see when limits reset
- **Notifications** — get alerted at 80% and 100% usage with customizable sounds
- **Custom notification sounds** — pick any .aiff, .wav, or .mp3
- **On-device only** — no cloud, no login, no tracking
- **Settings pane** — configure API keys, limits, reset hours, sounds

## Install

### From source
```bash
git clone https://github.com/ayussheth/usagebar.git
cd usagebar
swift build -c release
cp .build/release/UsageBar /usr/local/bin/usagebar
```

### Run
```bash
usagebar
```

Or add to Login Items to start automatically.

## Usage

- Click the gauge icon in your menu bar to see usage
- Click ⚙️ to configure services, limits, and notification sounds
- Click + on any service to manually log a usage
- Notifications fire at 80% (warning) and 100% (limit reached)

## Privacy

Everything stays on your Mac. Settings stored in `~/Library/Application Support/UsageBar/`.

## License

MIT
