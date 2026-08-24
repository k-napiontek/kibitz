# Contributing

## Adding your language

This is the most useful contribution you can make, and it needs no Swift.

kibitz explains mistakes in the learner's own language. What makes the advice
good is not the translation, it is knowing which mistakes speakers of *that*
language actually make in English. A Polish speaker drops articles because
Polish has none. A Spanish speaker does not, but overuses the present
continuous. Those patterns live in a per-language profile.

To add one:

1. Copy `Sources/KibitzCore/Resources/profiles/pl.md` to `<code>.md`, using the
   ISO 639-1 code for your language.
2. Rewrite it for your language. Keep the structure: a short heading per error
   class, then two or three real before-and-after examples with the category
   in brackets. Write the examples from mistakes you have actually made or
   seen, not from a textbook.
3. Add your language to `BundledPrompt.availableLanguages` in
   `Sources/KibitzCore/PromptTemplate.swift`. One line.
4. Add a case to the fixture corpus so your profile is covered by the tests.
5. Open a pull request.

A profile is worth more when it is opinionated and specific. Three sharply
observed patterns beat twenty generic ones.

## Working on the code

```
./scripts/test.sh          # runs the suite
swift build -c release
```

`scripts/test.sh` prefers Xcode via `DEVELOPER_DIR`, so you do not need to run
`sudo xcode-select -s`. It falls back to Command Line Tools with two workarounds,
because swift-testing ships there but is neither on SwiftPM's default search path
nor able to cross-import Foundation. The script explains both.

### Tests come first

This project is built test first. Every behaviour change starts with a failing
test, and the failure is observed before any implementation is written. If you
send a pull request with production code and no test that failed before it,
expect that to come up in review.

Two rules worth knowing before you write a test here:

- The `Gate` is the privacy boundary. Its secure-input and secure-field rules
  are not configurable and must not become configurable. Tests exist to pin
  that down; do not relax them.
- Fixtures under `Tests/KibitzCoreTests/Fixtures` are real captured model
  responses, not handwritten JSON. `cli-fenced-response.json` preserves a case
  where the model ignored the prompt and fenced its output. Keep it.

## Style

- English everywhere: code, comments, commits, pull requests.
- Conventional Commits: `type(scope): subject`, lowercase, imperative, under 72
  characters, no trailing period.
- Plain hyphens only. No em dashes, anywhere.
