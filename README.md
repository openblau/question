# Question

A macOS menu-bar app for quick lookups. Press **⌥Space** anywhere and a Spotlight-style box pops up so you can ask Claude. Answers stream in, with web search and source links.

Every session is incognito: the conversation lives only in memory and is gone when you press Esc or quit. Nothing is written to disk.

## Install

Requires macOS 15+ and Xcode / Swift 6.

```sh
./build.sh            # builds, installs to /Applications/Question.app, and launches it
./build.sh --no-launch
```

On first launch, paste your Anthropic API key (create one at console.anthropic.com → Settings → API Keys). You can change it later from the menu-bar icon → **Change API Key…**.

## Use

| Key | Action |
| --- | --- |
| ⌥Space | Open / hide the box |
| Return | Ask (follow-ups keep the conversation) |
| Esc | End the session and erase it from memory |
| ⌘N | New chat |

The menu-bar icon also has **Open at Login** (on by default after first launch), **Forget API Key**, and **Quit**.

## Privacy

- Conversations are never persisted: no history, logs, or cache. Requests use an ephemeral `URLSession`.
- The API key is stored in your login Keychain, readable only while the Mac is unlocked, and never synced to iCloud or migrated to another device. For development you can instead launch from a terminal with `ANTHROPIC_API_KEY` set.
- The only other thing saved is one flag in `~/Library/Preferences/com.openblau.question.plist`, which records that the login item was set up.
- What Anthropic retains on its side depends on your API organization's data retention settings.

## Configuration

Model and effort are set in `Sources/Question/ClaudeClient.swift` (`claude-opus-5-5`, effort `medium`). Web search (up to 5 searches per answer) and server-side refusal fallbacks are enabled there too.
