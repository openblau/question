# Question

A macOS menu-bar app for quick lookups. Press **⌥Space** anywhere and a Spotlight-style box pops up so you can ask Claude. Answers stream in as rich text (tables, lists, syntax-highlighted code with a copy button), with web search and source links.

It runs on either your Claude subscription or an Anthropic API key.

Every session is incognito: the conversation lives only in memory and is gone when you press Esc or quit. Nothing is written to disk.

## Install

Requires macOS 15+ and Xcode / Swift 6.

```sh
./build.sh            # builds, installs to /Applications/Question.app, and launches it
./build.sh --no-launch
```

## Sign in

Pick one under **Answer With** in the menu-bar icon's menu:

- **Claude Subscription** uses your Pro or Max plan through [Claude Code](https://claude.com/claude-code). Install it and run `claude` once in Terminal to log in; Question then runs it in the background, so there is nothing to paste. This is the default when Claude Code is installed and no API key is saved.
- **Anthropic API Key** bills your API account. Paste a key (create one at console.anthropic.com → Settings → API Keys). You can change it later with **Change API Key…**.

## Use

| Key | Action |
| --- | --- |
| ⌥Space | Open / hide the box |
| Return | Ask (follow-ups keep the conversation) |
| Esc | End the session and erase it from memory |
| ⌘N | New chat |

The menu-bar icon also has **Open at Login** (on by default after first launch), **Forget API Key**, and **Quit**. Switching between subscription and API key starts a new chat.

## Privacy

- Conversations are never persisted: no history, logs, or cache. API-key requests use an ephemeral `URLSession`.
- With a subscription, the conversation lives in a background `claude` process started with `--no-session-persistence`, so no transcript is written. Esc kills that process. It ignores your Claude Code settings, hooks, and MCP servers, and can only use web search. Claude Code may still update its own bookkeeping files under `~/.claude`.
- The API key is stored in your login Keychain, readable only while the Mac is unlocked, and never synced to iCloud or migrated to another device. For development you can instead launch from a terminal with `ANTHROPIC_API_KEY` set.
- The only other things saved are two settings in `~/Library/Preferences/com.openblau.question.plist`: that the login item was set up, and which sign-in you chose.
- What Anthropic retains on its side depends on your plan's or API organization's data retention settings.

## Configuration

Model and effort are set in `Sources/Question/ClaudeClient.swift` (`claude-opus-5-5`, effort `medium`). Both sign-in methods use them. For API keys, web search (up to 5 searches per answer) and server-side refusal fallbacks are enabled there too. The subscription path is in `ClaudeCodeClient.swift`, and answer styling is in `MarkdownView.swift` (built on [Textual](https://github.com/gonzalezreal/textual)).

## License

MIT. See [LICENSE](LICENSE).
