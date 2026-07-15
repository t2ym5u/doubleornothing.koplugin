# doubleornothing.koplugin

A **Double or Nothing Party** display plugin for [KOReader](https://github.com/koreader/koreader) — the classic "Quitte ou Double" bet-your-points quiz, played around the table.

## Concept

Teams take turns. On your turn, a question is shown — confer with your team, then reveal the answer. Get it right and you win the pot (1 point the first time, doubled every time after). At each correct answer you choose: bank the pot and end your turn safely, or risk it all on a new question to double it again.

The plugin ships with **4 example questions** in French and English — just enough to try the mechanic. Drop your own JSON file into KOReader's documents folder to play with a real deck.

## Rules

- Teams take turns. Each turn, one question at a time is shown to the active team.
- **✗ Wrong** — the team loses everything currently in the pot. Turn ends, pot resets to 0.
- **✓ Correct** — the pot is won (1 pt first time, then doubled each time). Choose:
  - **🏦 Bank** — add the pot to the team's score, turn ends.
  - **⚡ Double or Nothing** — draw a new question and risk the pot to double it.
- Teams swap after every turn, whether banked or busted.

## Features

- **Bank-or-double decision loop** — the core "Quitte ou Double" tension, reveal by reveal
- **Auto team rotation** — advances to the next team after each turn
- **2–6 teams** — configurable team count
- **Optional thinking timer** — 15 s to 45 s per question, or disabled
- **FR + EN UI** — interface language switchable; loads `doubleornothing_questions_fr.json` or `doubleornothing_questions_en.json` automatically
- **E-ink friendly** — only the timer digit refreshes in fast/A2 mode

## Bringing your own questions

To add or replace questions, create a file named `doubleornothing_questions_fr.json`
(or `doubleornothing_questions_en.json`, or `doubleornothing_questions.json`) and copy it to
KOReader's **documents** folder (`/sdcard/koreader/` on most devices). A file placed there takes
priority over the bundled example deck.

```json
[
  {
    "question": "What is the capital of Portugal?",
    "answer": "Lisbon",
    "category": "Geography"
  }
]
```

Each question object must have:
- `"question"` — the question text
- `"answer"` — the revealed answer
- `"category"` *(optional)* — shown as a badge above the question

Questions are shuffled on load and wrap around automatically.

## Controls

| Button | Action |
|--------|--------|
| **Commencer le tour / Start turn** | Begin the active team's turn |
| **Révéler la réponse / Reveal answer** | Show the answer to the current question |
| **✓ Juste / ✓ Correct** | The team answered correctly — win the pot |
| **✗ Faux / ✗ Wrong** | The team answered wrong — lose the pot, turn ends |
| **🏦 Encaisser / 🏦 Bank** | Bank the pot, turn ends |
| **⚡ Doubler / ⚡ Double** | Risk the pot on a new question to double it |
| **Options** | Language, teams, timer duration, reset |
| **Rules** | Show rules reminder |
| **Close** | Exit |

## Installation

### Via KOReader Plugin Manager

```
doubleornothing.koplugin/ → KOReader plugins/ folder
game-common/               → alongside plugins/ (shared library)
```

### Manual

1. Download `doubleornothing.zip` from [Releases](../../releases).
2. Extract to your KOReader `plugins/` directory.
3. Restart KOReader — **Double or Nothing Party** appears in the Tools menu.
4. Optionally copy your own `doubleornothing_questions_fr.json` (or `_en.json`) to KOReader's documents folder.

## Development

`doubleornothing.koplugin/` lives inside the
[koreader-plugins](https://github.com/t2ym5u/koreader-plugins) monorepo.

## License

GPL-3.0
