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
- **A Claude Max subscription or a DeepSeek API key.** kibitz has no hosted
  backend. You bring your own model access and you pay for your own usage.

## What it costs

kibitz is free. The model calls are not. Pick a backend from the menu bar:

| Backend | Auth | Latency per check | Cost per check |
|---|---|---|---|
| Claude subscription, via the `claude` CLI | Claude Max, no key | ~5-7 s | ~$0.03 of quota, up to ~$0.09 on a cold cache |
| DeepSeek API | API key in your Keychain | ~1.2 s | ~$0.0001 |

The subscription backend needs no API key and is the easiest way to start. It is
also, by a wide margin, the expensive one: the `claude` CLI ships its own system
prompt and tool definitions on every invocation, so a 40-character sentence goes
out as a ~22,000-token request. That overhead cannot be turned off while using a
subscription.

The DeepSeek backend sends the coaching prompt and nothing else, and DeepSeek's
prefix cache serves it back at $0.007-0.014 per million tokens. That is where
the 300x gap comes from.

The DeepSeek figures are measured on this machine, over five consecutive checks
of the same sentence, with the coaching prompt served from DeepSeek's prefix
cache. Speed is a property of their endpoint on the day you use it, so measure
it on yours:

```
swift run kibitz-check "I have 20 years and I work here since 2020." --backend deepseek
```

On the same 42-case corpus, DeepSeek caught 22 of 22 real mistakes and flagged
none of the 20 correct sentences, finishing the whole suite in 6 seconds.

**Automatic mode requires an API key.** Five seconds after you finished a
sentence, by which time you have typed two more, is worse than no popup at all,
so the app disables the toggle on the subscription backend rather than letting
you switch on a mode that would feel broken.

## Choosing a backend

Everything lives in the menu bar icon:

- **Backend** - Claude subscription or DeepSeek API. Nothing is switched for
  you: storing a key never silently reroutes your sentences.
- **DeepSeek model** - `deepseek-v4-flash` by default, `deepseek-v4-pro` when
  you want the better judgement and will pay 3x for it.
- **Set DeepSeek API key...** - stored in your login Keychain, never in the app
  bundle, a preferences file or an environment variable. Get one at
  platform.deepseek.com.

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
- Sentences that pass those checks are sent to whichever backend you selected,
  Anthropic or DeepSeek, and nowhere else. There is no telemetry and no server
  operated by this project. Which one you pick is a real privacy decision, and
  it is why the backend is an explicit menu choice rather than something the app
  infers from what is on your machine.
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
./scripts/test.sh          # 133 tests
swift build -c release
```

The name is Yiddish. A kibitzer is the person who watches over your shoulder
and offers advice you did not ask for. That is the entire product.

## License

MIT. See [LICENSE](LICENSE).
