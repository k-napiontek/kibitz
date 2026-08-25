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

## The weekly review

A week after the last one, kibitz opens a window with the mistakes worth
studying. Categories are ordered by how often you repeated them, because a
category you got wrong nine times is a habit and a habit is what a flashcard is
for. Seriousness only breaks ties: one bad slip you will never make again is
worth less study than nine small ones you make daily. Inside a category the
serious mistakes come first.

The categories kibitz mutes from the popup so they do not interrupt typing -
spelling, punctuation, capitalization - still appear here. They were never worth
a bubble mid-sentence; they are worth seeing once a week.

Tick the ones you want and export. You get a plain tab-separated file:

```
#separator:tab
#html:true
#tags column:3

I work here since 2020.    I have worked here since 2020.<br>'since 2020' wymaga present perfect.    kibitz tense high
```

Import it with Anki's **File > Import** using the **Basic** note type. The header
lines set the field mapping and the tags column for you. The front is the
sentence you actually wrote, the back is the fix with the changed words in bold
followed by the explanation in your language, and each card is tagged `kibitz`
plus its category and severity.

Exported mistakes are marked, so next week's review does not offer you a card you
already made. They still count towards their category, because "you got articles
wrong nine times" stays true whether or not you made the card.

Nothing waits for a timer to fire. Being due is recomputed from a stored date
every time, so a laptop that spent the week asleep comes back to one review
waiting, not a backlog of them. A review that comes due with nothing in it stays
quiet. You can open it whenever you like from the menu bar.

## Requirements

- macOS 26 or later, Apple Silicon
- Homebrew, which is how kibitz is installed
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

```
brew install k-napiontek/tap/kibitz
kibitz
```

The first command pours a prebuilt app. Nothing is compiled on your machine and
there is no Gatekeeper warning to click through. The second one starts it, which
is the one thing a package manager should not do for you.

kibitz then asks for the Accessibility permission, which it needs to read the
sentence you just finished, and adds itself to your login items. Turn that off
whenever you like from the menu bar: **Start at login**.

### Why this is a formula and not a cask

A downloaded app has to be notarised by Apple to open without a warning, and
notarisation needs a paid developer account. The usual workaround is to tell you
to run `xattr -dr com.apple.quarantine` on it, which is the same instruction
malware gives, so this project will not ask that of you. Homebrew agrees: it
dropped `--no-quarantine` in 4.7 and stops supporting casks that fail Gatekeeper
on 1 September 2026.

None of that applies here, because the quarantine attribute is something
**casks** apply to downloads. A formula bottle is a tarball that `brew` extracts,
the same as every command line tool you have installed, so it is never marked
and Gatekeeper's notarisation check never fires. You can confirm it rather than
take my word for it:

```
xattr $(brew --prefix)/opt/kibitz/Kibitz.app     # prints no com.apple.quarantine
```

The app is signed ad-hoc, which is all Apple Silicon asks of code that is not
quarantined. The bottle is built in GitHub Actions on a `v*` tag and the formula
is generated from what was actually published, so the checksums in the tap
cannot drift from the artifact.

If you are on hardware the bottle was not built for, `brew` falls back to
compiling from source and you will need the Command Line Tools. Everyone on a
supported Mac pours the prebuilt one.

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
- **Browsers get asked to open up, once.** Chromium and Electron hide their
  content from Accessibility until a client asks for it, which is why the hotkey
  used to do nothing on a web page. The first time a read fails in an app,
  kibitz asks that app to expose its tree - the same request VoiceOver makes.
  Apps that already expose their text are never asked, and no app is asked twice.
- **When an app exposes nothing at all**, terminals in particular, kibitz falls
  back to copying your selection with a synthesized Cmd+C, then puts your
  clipboard back. It happens only when you press the hotkey, only when
  Accessibility read nothing, and never when the clipboard holds anything but
  text - an image or a file is left untouched and the copy is not even attempted.
- Sentences that pass those checks are sent to whichever backend you selected,
  Anthropic or DeepSeek, and nowhere else. There is no telemetry and no server
  operated by this project. Which one you pick is a real privacy decision, and
  it is why the backend is an explicit menu choice rather than something the app
  infers from what is on your machine.
- **Correct sentences are counted, never stored.** The review can tell you that
  82 sentences were checked and 14 had a mistake without the log accumulating
  everything you have ever typed. Only the mistakes keep their text.
- The mistake log is a plain SQLite file at
  `~/Library/Application Support/kibitz/mistakes.sqlite`, beside the diagnostics.
  Read it with `sqlite3` whenever you are curious about what it holds. Delete it
  whenever you like - **Mistake log > Delete the mistake log...** in the menu
  bar does it, and kibitz keeps working with a fresh one.

macOS ties the Accessibility grant to the exact binary, so **after a
`brew upgrade` you will be asked to grant it again.** That is macOS behaving
correctly, not a bug. It stays granted between updates. Your login item is not
affected: it follows the app rather than the version it was created from.

Uninstalling is `brew uninstall kibitz`. That removes the app and nothing else -
your mistake log under `~/Library/Application Support/kibitz` and your login item
are yours to keep or remove, and the menu offers to delete the log for you.

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
./scripts/test.sh          # 211 tests
swift build -c release
```

The name is Yiddish. A kibitzer is the person who watches over your shoulder
and offers advice you did not ask for. That is the entire product.

## License

MIT. See [LICENSE](LICENSE).
