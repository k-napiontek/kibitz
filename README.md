# kibitz

**Instant English writing feedback on macOS, explained in your own language.**

You write English all day in Slack, notes and commit messages. You make the same
handful of mistakes over and over, nobody corrects them, and a spell checker
never will. kibitz watches the sentences you finish, and when one is wrong in a
way worth learning from, it shows a small bubble with the fix and a one-line
explanation **in your native language**.

Correct sentences produce nothing at all.

<!-- TODO: replace with a screen recording of the popup. This is the single
     most important thing in this README for adoption. -->
![kibitz in action](docs/demo.gif)

## Why not just use a grammar checker

Grammar checkers tell you *what* to change. kibitz tells you *why*, in the
language you actually think in, and remembers what you keep getting wrong.

```
You typed:  I have 20 years and I work here since 2020.
kibitz:     I am 20 years old and I have worked here since 2020.
            Wiek podajemy przez 'to be', a 'since 2020' wymaga present perfect.
```

It also catches the mistakes that are grammatically legal but that no native
speaker would produce, which is the category most learners never get feedback
on.

Every correction goes into a local SQLite log. Once a week kibitz shows you the
mistakes you actually repeat, and you pick which ones become Anki cards.

## Requirements

- macOS 26 or later, Apple Silicon
- Xcode Command Line Tools, because kibitz compiles on your machine. Run
  `xcode-select --install` if you do not have them.
- **A Claude Max subscription or an Anthropic API key.** kibitz has no hosted
  backend. You bring your own model access and you pay for your own usage.

## What it costs

kibitz is free. The model calls are not. Measured on Claude Sonnet 5:

| Backend | Latency per check | Cost per check |
|---|---|---|
| Claude Max subscription, via the `claude` CLI | ~5 s | ~$0.031 of quota |
| Anthropic API key | ~0.5 s | ~$0.0012 |

The subscription backend needs no API key and is the easiest way to start, but
it is roughly 25x more expensive per check and far too slow to check sentences
as you type. **Automatic mode requires an API key.** The app tells you this
rather than letting you switch on a mode that would feel broken.

## Install

Not released yet. When it is:

```
brew install k-napiontek/tap/kibitz
```

kibitz is distributed as source and built on your Mac, not as a prebuilt
binary. That is deliberate. A downloaded binary has to be notarised by Apple to
open without a warning, which requires a paid developer account, and the
alternative is telling you to run `xattr -dr com.apple.quarantine` on an app
that reads what you type. That is the same instruction malware gives, so this
project does not ask it of you.

Building locally sidesteps the question entirely. The tradeoff is that you need
the Command Line Tools installed, which most developers already do.

## Permissions and privacy

kibitz needs the Accessibility permission to read the text field you are typing
in. That is a serious permission and you should be sceptical of any app that
asks for it. Here is exactly what it does:

- **The app allowlist starts empty.** Nothing is monitored until you explicitly
  add an app. Automatic mode is opt in, per application.
- **Secure input is a hard stop.** If macOS reports secure input is active,
  kibitz captures nothing at all. This is not configurable.
- **Password fields are a hard stop.** A focused secure text field is never
  read. This is not configurable.
- **Your own language stays local.** Text that is not English is discarded
  before any network call, so writing in your native language sends nothing.
- Sentences that pass those checks are sent to Anthropic to be checked. Nothing
  is sent anywhere else. There is no telemetry and no server operated by this
  project.
- The mistake log is a plain SQLite file on your machine. Delete it whenever
  you like.

macOS ties the Accessibility grant to the exact binary, so **after an update you
will be asked to grant it again.** That is macOS behaving correctly, not a bug.
It stays granted between updates.

## Adding your language

kibitz is not a Polish tool that happens to be open source. The explanation
language is a setting, and the interference patterns for each first language
live in their own file.

Polish ships today. Adding yours is a self-contained pull request: one profile
describing the mistakes speakers of your language typically make in English.
See `CONTRIBUTING.md`.

## Building from source

```
git clone https://github.com/k-napiontek/kibitz
cd kibitz
./scripts/test.sh          # 58 tests
swift build -c release
```

The name is Yiddish. A kibitzer is the person who watches over your shoulder
and offers advice you did not ask for. That is the entire product.

## License

MIT. See [LICENSE](LICENSE).
