# BunpoTester / JLPT Grammar Drill — Developer Documentation

This document describes the app's structure, the three drill modes, and the
FSRS spaced repetition scheduler in detail.

If this document conflicts with the code, the code is authoritative. Source
files are the source of truth; this document is a map.

---

## Table of contents

1. [App overview](#1-app-overview)
2. [Top-level architecture](#2-top-level-architecture)
3. [Persistence model (SwiftData)](#3-persistence-model-swiftdata)
4. [Content: grammar, particles, and audio](#4-content-grammar-particles-and-audio)
5. [FSRS — the spaced repetition scheduler](#5-fsrs--the-spaced-repetition-scheduler)
    1. [FSRS overview](#51-fsrs-overview)
    2. [The FSRS card state](#52-the-fsrs-card-state)
    3. [The four ratings](#53-the-four-ratings)
    4. [The scheduler instance](#54-the-scheduler-instance)
    5. [How `SRSEngine` wraps FSRS for grammar/particles](#55-how-srsengine-wraps-fsrs-for-grammarparticles)
    6. [How `AudioSRSService` wraps FSRS for audio](#56-how-audiosrsservice-wraps-fsrs-for-audio)
    7. [Mastery levels — turning FSRS state into UI](#57-mastery-levels--turning-fsrs-state-into-ui)
    8. [End-to-end trace: one grammar session](#58-end-to-end-trace-one-grammar-session)
    9. [End-to-end trace: one audio session](#59-end-to-end-trace-one-audio-session)
6. [Session building](#6-session-building)
7. [Settings & user preferences](#7-settings--user-preferences)
8. [Schema migration safety net](#8-schema-migration-safety-net)
9. [Glossary](#9-glossary)

---

## 1. App overview

BunpoTester (target name `JLPTGrammarDrill`) is a SwiftUI iOS app for studying
Japanese grammar for the JLPT (Japanese Language Proficiency Test). It offers
three independent drill modes:

- **Grammar Drill** — multiple-choice cloze (fill-in-the-blank) exercises over
  JLPT N1–N5 grammar patterns. Each pattern has several example sentences;
  one pattern is one SRS "card".
- **Particle Practice** — multiple-choice drilling of Japanese particles
  (は, が, を, に, で, …). Each particle exercise is itself an SRS card
  under the same record table as grammar, distinguished by the `part_`
  prefix on its id.
- **Audio Drill** — the user is shown an English translation, records
  themselves speaking the Japanese sentence, and the app uses on-device
  speech recognition to grade the attempt. Each sentence is its own SRS card.

All three modes share the same FSRS scheduling engine, but they store their
state in different SwiftData models (see §3).

---

## 2. Top-level architecture

Files live under `BunpoTester/`. App code is in `BunpoTester/JLPTGrammarDrill/`;
`SettingsView.swift` and `FontSizeManager.swift` sit one level up at the
`BunpoTester/` root.

```
JLPTGrammarDrillApp.swift     ── @main, sets up the SwiftData ModelContainer
├─ ContentView.swift          ── Hub view with cards for the three drills + Stats + Settings
├─ HomeView.swift             ── Grammar Drill home / session start
├─ ExerciseView.swift         ── Grammar drill session screen
├─ ParticlePracticeView.swift ── Particles drill screen
├─ AudioDrillHomeView.swift   ── Audio drill home / queue start
├─ AudioDrillView.swift       ── Audio drill session screen
├─ AudioDrillSettingsView.swift ── Audio-drill-specific settings sheet
├─ AudioHistoryView.swift     ── Past audio attempts browser
├─ GrammarBrowserView.swift   ── Browse-all-patterns list view
├─ StatsView.swift            ── Cross-mode mastery dashboard
├─ SettingsView.swift         ── (at BunpoTester/ root) JLPT levels, font scale, etc.
│
│ Data + persistence ───────────────────────────
├─ SRSRecord.swift            ── @Model — one row per grammar/particle pattern
├─ AudioCard.swift            ── @Model — one row per audio sentence
├─ AudioAttempt.swift         ── @Model — one row per audio recording attempt
├─ StudyLog.swift             ── @Model — daily activity counter (for streak)
│
│ Scheduling ──────────────────────────────────
├─ SRSEngine.swift            ── Thin wrapper around SwiftFSRS for grammar/particles
├─ AudioSRSService.swift      ── Audio queue builder + FSRS wrapper for audio
├─ SessionBuilder.swift       ── Picks which grammar cards to show today
├─ ParticleSessionBuilder.swift ── Picks particle exercises
├─ AudioDrillSettings.swift   ── @AppStorage-backed audio drill knobs + defaults
│
│ Content loading ─────────────────────────────
├─ GrammarLoader.swift        ── Loads n*_*.json into [GrammarPoint]
├─ ParticleLoader.swift       ── Loads particles-exercises.json
├─ AudioBrowserView.swift     ── Loads + browses audio exercises (contains AudioExerciseLoader)
├─ GrammarPoint.swift         ── Bundled grammar content model
├─ ParticlePoint.swift        ── Bundled particle content model
├─ AudioExercise.swift        ── Bundled audio content model
│
│ Speech ──────────────────────────────────────
├─ JapaneseSpeaker.swift            ── AVSpeechSynthesizer wrapper (TTS)
├─ SpeechRecognitionService.swift   ── Recording + recognition coordinator
├─ SFSpeechRecognitionService.swift ── On-device SFSpeech wrapper
├─ SpeechAnalyzerService.swift      ── (parallel iOS 26 SpeechAnalyzer path)
├─ AnswerMatcher.swift              ── Grades the recognised string
└─ TextNormalizer.swift             ── Normalises Japanese strings for comparison
│
│ UI helpers ──────────────────────────────────
└─ FontSizeManager.swift      ── (at BunpoTester/ root) font scaling utilities
```

External package: **[SwiftFSRS](https://github.com/open-spaced-repetition/SwiftFSRS)** — provides
the FSRS algorithm itself (`Card`, `Rating`, `Scheduler`, `FSRSAlgorithm.v5`).

---

## 3. Persistence model (SwiftData)

The app uses Apple's SwiftData with four `@Model` types, all registered in
`JLPTGrammarDrillApp.modelContainer`:

| Model         | Identity                  | Purpose                                                                                                  |
| ------------- | ------------------------- | -------------------------------------------------------------------------------------------------------- |
| `SRSRecord`   | `grammarId` (unique)      | FSRS card state + accuracy counters for one grammar pattern *or* one particle exercise (`part_` prefix). |
| `AudioCard`   | `exerciseId` (unique)     | FSRS card state for one audio sentence.                                                                  |
| `AudioAttempt`| (implicit)                | A log row for every audio recording the user makes (and synthetic "too easy" markers).                   |
| `StudyLog`    | `dateKey` (yyyy-MM-dd)    | Per-day count of items studied — drives the streak banner and the 14-day chart.                          |

Important quirks:

- `SRSRecord` is **shared between Grammar and Particles**. They are
  distinguished only by the id prefix: particle records have ids that start
  with `part_`. `StatsView` uses this prefix check (`hasPrefix("part_")`) to
  split them back out for separate displays.
- `Card` is a Swift **value type** from SwiftFSRS, so each model stores its
  fields individually (`fsrsDue`, `fsrsStability`, `fsrsDifficulty`, …) and
  reconstructs a `Card` on demand via the `fsrsCard` computed property.
  See `SRSRecord.swift:41` and `AudioCard.swift:42`.
- `fsrsStatusRaw: Int` maps to `SwiftFSRS.Status`:
  - `0` = `.new`
  - `1` = `.learning`
  - `2` = `.review`
  - `3` = `.relearning`

This raw integer is what's persisted, with explicit switch statements
translating in both directions. This avoids relying on a `Codable` /
`RawRepresentable` conformance the library might or might not provide for its
enum.

---

## 4. Content: grammar, particles, and audio

All study content ships in the app bundle as JSON files.

- **Grammar** — `n1_001.json` … `n5_NNN.json` (531 files in
  `JLPTGrammarDrill/` at time of writing). Each file describes one grammar
  pattern plus several example sentences, the answer to blank out, and a list
  of plausible-wrong distractor choices with per-distractor explanations. The
  id is the filename stem (`"n1_001"`). The id prefix doubles as the JLPT
  level — see `StatsView.level(fromId:)` at `StatsView.swift:145`.
- **Particles** — a single `particles-exercises.json` file (~100 entries
  covering は/が/を/に/で/etc.) loaded by `ParticleLoader`. Each exercise has
  id `part_NNN` (the particle character is a separate field, not part of the
  id).
- **Audio** — JSON files describing sentences with one or more acceptable
  written forms (`exampleSentence`, `acceptableTranscriptions`). The audio
  drill compares the user's speech-recognised text against these.

Loaders are bundle-only and synchronous; bundle content never changes at
runtime, so `StatsView` caches loader results in `@State` and re-loads only
when empty (`StatsView.swift:167`).

---

## 5. FSRS — the spaced repetition scheduler

### 5.1 FSRS overview

**FSRS** (Free Spaced Repetition Scheduler) is an open-source algorithm for
deciding *when* to next review a flashcard. Compared to the SuperMemo-2 (SM-2)
algorithm used by Anki for years, FSRS:

- models each card with two latent numbers — **stability** (how long the
  memory will last) and **difficulty** (how hard the card is for the learner);
- predicts the learner's probability of recalling each card at a given moment
  based on those two numbers and the time elapsed since the last review;
- schedules the next review for whenever the recall probability would drop to
  a target retention (default ≈ 90%); and
- updates stability and difficulty after each review using parameters fit
  from millions of real-world reviews.

A `.good` recall extends the interval; a `.again` recall shortens it. As the
user demonstrates retention, cards drift toward longer intervals. That
long-interval drift is what defines "mastered" in the UI.

The app uses FSRS **v5** via the SwiftFSRS package's `ShortTermScheduler` —
see `SRSEngine.swift:7`. Grammar and particles use two of the four FSRS
grades (see §5.3); audio uses all four.

### 5.2 The FSRS card state

A SwiftFSRS `Card` has these fields, all mirrored on both `SRSRecord` and
`AudioCard`:

| Field            | Meaning                                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `due: Date`      | When the card is next supposed to be reviewed. The scheduler sets this on every grade.    |
| `stability`      | How many days the memory is currently estimated to last. Grows with successful reviews.   |
| `difficulty`     | A latent per-card difficulty score. Grows on failed reviews, shrinks on successful ones.  |
| `elapsedDays`    | Days between the previous review and the one being scheduled. Set by the scheduler.       |
| `scheduledDays`  | Days from the most recent review to `due`. Used to derive mastery levels (§5.7).          |
| `reps`           | Total review count.                                                                       |
| `lapses`         | Number of times the card was forgotten (rated `.again` while in review state).            |
| `status`         | `.new` → `.learning` → `.review` → (`.relearning` on a lapse).                            |
| `lastReview`     | Date of the most recent review.                                                           |

`scheduledDays` serves as a proxy for retention strength because it grows
monotonically with successful reviews. The UI buckets it into the mastery
levels described in §5.7.

### 5.3 The four ratings

FSRS expects one of four grades per review:

- `.again` — forgot, reset (or near-reset) the interval.
- `.hard`  — recalled but with effort; interval grows slowly.
- `.good`  — recalled comfortably; default success grade.
- `.easy`  — trivial recall; interval grows aggressively.

**Grammar and particles** use only `.good` (fully correct) and `.again` (any
first-try mistake); see `SRSEngine.rating(correct:)` at `SRSEngine.swift:16`.
There is no UI for the user to self-report effort, so finer-grained signal is
not collected.

The aggregate path (§5.5) is an exception: it emits `.hard` when the user
gets ≥50% but not 100% of a pattern's sentences right on the first try,
providing FSRS with a partial-credit signal derived from per-sentence results
rather than from user self-report.

**Audio drill** uses all four grades:

- `.again` — failed and chose "Skip and move on" (`AudioDrillView.swift:489`).
- `.good`  — passed the speech-recognition threshold and tapped "Next"
  (`AudioDrillView.swift:478`).
- `.easy`  — tapped "Too easy — skip" before recording (button at
  `AudioDrillView.swift:155`; rating applied inside
  `AudioSRSService.markTooEasy` at `AudioSRSService.swift:137`).

`.hard` is unused on audio; the result panel exposes no equivalent control.

### 5.4 The scheduler instance

```swift
nonisolated let fsrsScheduler: any Scheduler = SchedulerType.shortTerm.implementation
```
— `SRSEngine.swift:7`

A single global scheduler instance, declared `nonisolated` so both the
`@MainActor`-bound `AudioSRSService` and the plain `SRSEngine` static methods
can call it without actor hops. SwiftFSRS's `ShortTermScheduler()` is not
public, but `SchedulerType.shortTerm.implementation` is, and resolves to the
same value.

Every scheduling call has the same shape:

```swift
let review = fsrsScheduler.schedule(
    card: <current Card>,
    algorithm: FSRSAlgorithm.v5,
    reviewRating: <Rating>,
    reviewTime: <Date>
)
// review.postReviewCard is the updated Card to persist.
```

`FSRSAlgorithm.v5` is always passed; there is no in-app setting to change
algorithm version. Any migration to a future version should be done explicitly,
with the persisted parameters migrated at the same time.

### 5.5 How `SRSEngine` wraps FSRS for grammar/particles

`SRSEngine` (`SRSEngine.swift`) is a stateless helper exposing two entry
points used by the drill views:

#### `aggregateRating(correct:total:) -> Rating?`

The grammar drill shows **multiple sentences for one pattern in the same
session** (typically 3 intro sentences for a new pattern; 1 for a review).
FSRS expects **one review per card per session**, not one per sentence.
Per-sentence first-try outcomes are therefore accumulated in
`ExerciseView.patternOutcomes` during the session and collapsed into one
rating at end of session:

| First-try correct        | Resulting rating |
| ------------------------ | ---------------- |
| 100%                     | `.good`          |
| ≥ 50% and < 100%         | `.hard`          |
| < 50%                    | `.again`         |
| 0 attempts               | `nil` (skip)     |

See `SRSEngine.swift:28` and the call site at `ExerciseView.flushPatternRatings()`
in `ExerciseView.swift:500`. A `nil` return signals the caller to skip the
record — applies when the session ended before the user answered anything for
a given pattern.

#### `applyRating(record:rating:attemptsDelta:correctDelta:reviewTime:)`

Runs the scheduler once and writes the result back to the SwiftData row.
`attemptsDelta` and `correctDelta` allow the caller to bump local accuracy
counters by **every on-screen answer** (including retries), even though FSRS
sees only one synthetic rating per session. This keeps the displayed accuracy
percentage aligned with the user's on-screen activity.

See `SRSEngine.swift:40`. The legacy `processAnswer(record:correct:)` at
`SRSEngine.swift:62` is the original per-answer path; the particle drill
still uses it because a particle exercise *is* the SRS card (1:1 mapping).
Grammar uses `applyRating` exclusively.

### 5.6 How `AudioSRSService` wraps FSRS for audio

`AudioSRSService` (`AudioSRSService.swift`) is the audio-side equivalent of
`SRSEngine` with one additional responsibility: it also owns **queue building**
for the audio drill, including the engagement-gated new-card introduction
system described below.

Key methods:

- `buildQueue(activeLevels:dailyNewCardBudget:learningPoolCap:now:)` —
  assembles the play queue:
  1. Collect all `AudioCard`s whose `fsrsDue ≤ now` and whose exercise is in
     an enabled JLPT level (the review items).
  2. Compute the day's new-card allowance: `dailyNewCardBudget` minus the
     number already introduced today (`introducedTodayCount`). If the current
     learning pool exceeds `learningPoolCap`, the allowance drops to zero.
  3. Randomly pick that many never-seen exercises from the eligible levels.
  4. Interleave: one new card after every 4 reviews. If there are no
     reviews, all new cards appear first.

- `ensureCard(for:)` — fetch or lazily create an `AudioCard`. Deliberately
  **does not** set `introducedAt`, so the "Too easy" path does not consume
  the daily new-card budget.

- `markIntroduced(card:)` — stamps `introducedAt = now` if unset. Called
  from `AudioDrillView.stopRecording()` on the **first real recording
  attempt** for a card, so only cards the user has actually engaged with
  count against the daily quota.

- `grade(card:rating:now:)` — the scheduler call. Identical in shape to the
  grammar path.

- `markTooEasy(exercise:)` — graduates a card straight to `.easy` without
  marking it introduced. Invoked when the user taps "Too easy — skip" before
  recording; the card jumps directly into the long-interval review pool.

A card counts against the daily new-card budget only once the user engages
with it (first real recording), not when it first appears on screen. Defaults
live in `AudioDrillSettings` (`defaultDailyNewCardBudget = 5`,
`defaultLearningPoolCap = 15`).

### 5.7 Mastery levels — turning FSRS state into UI

Both `HomeView` and `StatsView` translate FSRS's continuous `scheduledDays`
into discrete mastery levels for display. They agree on the thresholds:

| Mastery level | `scheduledDays` (i.e. current interval) |
| ------------- | --------------------------------------- |
| Unseen        | no record exists                        |
| Learning      | < 3 days                                |
| Familiar      | ≥ 3 and < 14 days                       |
| Confident     | ≥ 14 and < 60 days                      |
| Mastered      | ≥ 60 days                               |

Defined in:
- `HomeView.MasteryLevel.level(for:)` (`HomeView.swift:58`)
- `StatsView.bucket(forScheduledDays:)` (`StatsView.swift:45`)

These thresholds are a UX choice, not an FSRS requirement. The `StatsView`
legend text exposes them to the user
("Learning <3d · Familiar 3–14d · Confident 14–60d · Mastered ≥60d.").

### 5.8 End-to-end trace: one grammar session

A single grammar session start-to-finish, with file:line citations:

1. **User taps "Start session"** on `HomeView`.
2. `SessionBuilder.buildSession(...)` (`SessionBuilder.swift:61`) fetches all
   `SRSRecord`s, sorts those whose `fsrsDue ≤ now` by how overdue they are,
   takes up to 10, then adds `newCount` patterns the user hasn't seen yet.
   For each truly-new pattern, it inserts a brand-new `SRSRecord` (status
   `.new`) and saves the context.
3. The session is a flat `[SessionExercise]`: 1 sentence per review pattern,
   3 sentences per new pattern.
4. `ExerciseView` mounts. `initializeSession()` (`ExerciseView.swift:283`)
   collects the unique pattern ids, sets `requiredStreaks` per pattern (3 for
   grammar, 1 for particles), and builds the queue.
5. The user answers each question. `handleAnswer(_:for:)` does three things:
   - updates the in-memory streak / completedPatterns state,
   - on a wrong answer, **inserts retry exercises** into the queue (immediate
     re-test in position 1, plus more retries spread further out),
   - calls `recordOutcome(correct:for:)` which appends to
     `patternOutcomes[item.grammarId]` and to `StudyLog`.
6. **No FSRS call happens during the session** — scheduling is deferred to a
   single batched call at end-of-session.
7. On any exit path (`advanceToNext` finishing the queue, the X button,
   `onDisappear`), `flushPatternRatings()` runs once
   (`ExerciseView.swift:500`):
   - For each pattern in `patternOutcomes`, compute first-try correct/total,
   - Get the `Rating` from `SRSEngine.aggregateRating`,
   - Fetch the `SRSRecord` by `grammarId`,
   - Call `SRSEngine.applyRating(...)`,
   - Save the context.

   The `didFlushRatings` guard makes the function idempotent — `advanceToNext`
   calls it, then `dismiss()` triggers `onDisappear` which calls it again, and
   the second call is a no-op.

8. On return to `HomeView`, the `@Query private var srsRecords` re-evaluates
   and the mastery counts redraw.

### 5.9 End-to-end trace: one audio session

1. **User taps "Start drill"** on `AudioDrillHomeView`.
2. `AudioSRSService.buildQueue(...)` assembles the queue (see §5.6).
3. `AudioDrillView` mounts with the queue.
4. For each item:
   - User taps the mic, records, taps stop.
   - `stopRecording()` (`AudioDrillView.swift:410`) runs SFSpeech, then
     `AnswerMatcher.match(...)` to compute the score.
   - It records a `StudyLog` and an `AudioAttempt` row.
   - `srs.ensureCard(for:)` + `srs.markIntroduced(card:)` — note this
     happens on the **first real recording**, not on the "Too easy" path.
   - Result phase appears with `PASS`/`FAIL` badge.
5. On PASS: user taps Next → `applyPass` calls `srs.grade(card:rating:.good)`.
   On FAIL: user can retry, or tap Skip → `srs.grade(card:rating:.again)`.
   On Too easy: `markTooEasy` calls `grade(...rating:.easy)` directly.
6. Each `grade(...)` call goes through SwiftFSRS and writes the updated
   fields back to the `AudioCard`.
7. Index advances; queue empties; finished view.

Unlike the grammar drill, FSRS calls happen **per item**, not deferred to end
of session. Each audio sentence *is* a card, so there is no
pattern-to-sentence many-to-one relationship to aggregate over.

---

## 6. Session building

Two session builders:

- **`SessionBuilder`** (`SessionBuilder.swift`) — grammar.
  Inputs: all loaded `GrammarPoint`s, the exercise pool keyed by grammarId,
  the `ModelContext`, and `newCount` (from `@AppStorage defaultNewPatterns`,
  default 1). Enforces a hard cap of 10 review items per session
  (`maxReview = 10` at `SessionBuilder.swift:53`/`105`). Selection prefers
  the **most overdue** items rather than the most recently due, so older
  deferrals clear first.

- **`ParticleSessionBuilder`** (`ParticleSessionBuilder.swift`) — particles.
  Uses the same most-overdue-first selection as `SessionBuilder`; there is no
  accuracy weighting. Differences from grammar: the new-count default is **3**
  (key `particleDefaultNewPatterns`, vs. `1` for grammar), and the builder
  takes a `maxItems` cap rather than a fixed review ceiling — reviews fill
  the cap first, then new items take any remaining slots.

Both insert new `SRSRecord` rows for never-seen items so the FSRS state
exists by the time the session screen mounts. `ParticleSessionBuilder` defers
the insert until after the cap is applied, so dropped items don't leave
phantom records behind.

---

## 7. Settings & user preferences

Almost all settings are `@AppStorage`-backed `UserDefaults` keys, requiring
no SwiftData migration when changed.

| Key                              | Default            | Where                              |
| -------------------------------- | ------------------ | ---------------------------------- |
| `enabledJLPTLevels`              | `"N5,N4,N3,N2,N1"` | `SettingsView`                     |
| `defaultNewPatterns`             | `1`                | `SessionBuilder`                   |
| `particleDefaultNewPatterns`     | `3`                | `ParticleSessionBuilder`           |
| `combinedDrills`                 | `false`            | `SettingsView`                     |
| `audio.threshold`                | `0.75`             | `AudioDrillSettings`               |
| `audio.lenientFinalParticles`    | `true`             | `AudioDrillSettings`               |
| `audio.dailyNewCardBudget`       | `5`                | `AudioDrillSettings`               |
| `audio.learningPoolCap`          | `15`               | `AudioDrillSettings`               |
| `audio.activeLevelsCSV`          | `"N5"`             | `AudioDrillSettings`               |
| `audio.voiceIdentifier`          | `""`               | `AudioDrillSettings`               |
| `fontScale`                      | (from manager)     | `FontSizeManager`                  |
| `lastStudyDate`, `streakCount`   | —                  | `ExerciseView.updateStreak()`      |

The audio drill keeps a **separate** active-levels setting from the grammar
drill. Grammar drives off `enabledJLPTLevels`; audio drives off
`audio.activeLevelsCSV`. The defaults differ (all levels vs. only N5)
because the audio drill is much heavier per item and its expected pace is
slower.

---

## 8. Schema migration safety net

`JLPTGrammarDrillApp.init` (`JLPTGrammarDrillApp.swift:9`) wraps
`ModelContainer` creation in a guarded fallback:

1. Try to open the existing store.
2. If it fails, check whether the error is a recognised CoreData
   schema-mismatch error code (`NSPersistentStoreIncompatibleVersionHashError`,
   `NSMigrationError`, etc., including unwrapping `NSUnderlyingErrorKey`).
3. **If it's not a schema mismatch**, crash. User data is not silently
   wiped on transient errors (disk full, sandbox glitch, file lock).
4. If it is, **move** (not delete) the `.store`, `-wal`, and `-shm` files
   into a timestamped `Backups/` directory next to the original, then retry
   container creation with an empty store.

A breaking model change therefore resets the user's in-app progress but
preserves the underlying data on disk for manual recovery. This is an
intentional trade-off: a full SwiftData migration would be significantly
more code to maintain while the model is still changing frequently.

---

## 9. Glossary

- **FSRS** — Free Spaced Repetition Scheduler. The algorithm that decides
  when to next review a card.
- **SwiftFSRS** — The Swift package that implements FSRS. Source of `Card`,
  `Rating`, `Scheduler`, `FSRSAlgorithm`.
- **Stability** — FSRS's estimate of how many days the memory will last,
  per card.
- **Difficulty** — FSRS's estimate of how hard a particular card is for the
  current user. Higher values lead to shorter intervals.
- **Scheduled days** — The interval between the last review and the next
  due date. Used by the UI to bucket cards into mastery levels.
- **Lapse** — A `.again` rating on a card that was in `.review` state.
  Increments `lapses` and demotes the card to `.relearning`.
- **Learning pool** — Cards currently in `.learning` or `.relearning`. The
  audio drill caps the size of this pool to prevent the user from
  accumulating too many in-flight new cards.
- **Engagement-gated introduction** — Counting a card against the daily
  new-card budget only once the user engages with it (first real recording),
  not at the moment it is first shown.
- **Aggregate rating** — In the grammar drill, the single FSRS rating
  produced from many sentence-level outcomes for one pattern in one session.
- **First-try correct** — Whether the user got a sentence right on the
  *first* attempt within a session. Retries do not overwrite this flag, so
  the aggregate rating reflects retention rather than persistence.
- **JLPT levels** — Japanese Language Proficiency Test levels N5 (beginner)
  through N1 (advanced). Used to filter content.
