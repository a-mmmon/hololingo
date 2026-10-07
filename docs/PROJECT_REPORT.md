# Hololingo — Project Report

**Package name:** `ar_language_app`
**Description:** Object-scanning vocabulary learning app — point your phone camera at real-world objects, get the object identified by an on-device ML model, and learn its word/definition/pronunciation through an AR overlay, flashcards, quizzes, and social/gamified features.

---

## 1. High-Level Concept

Hololingo turns everyday physical objects into vocabulary lessons:

1. The user scans a real object with the camera (`live_scanner_tab.dart`).
2. An on-device YOLO object-detection model (`assets/Models/best.tflite`) identifies it.
3. A cutout of the object is produced (iOS Vision foreground segmentation), the word is looked up in a bundled dictionary, and the result is shown as an AR overlay anchored to the camera feed (`ar_anchor_screen.dart`).
4. The word is saved to the user's Firestore-backed vocabulary, and can be reviewed later via flashcards, quizzes, and a spaced-repetition-style review screen.
5. A "Gobot" AI chat companion (Gemini via Firebase AI Logic) and a floating animated mascot rig provide personality/feedback throughout the scanning flow.
6. Social features (friends, invites, group events/gameplay) and topic-based guided lessons round out the app.

---

## 2. Architecture

The app is a single Flutter client with Firebase as its backend-as-a-service — there is no custom server. It follows a lightweight **screen + service** structure rather than a formal state-management framework (no Provider/Riverpod/Bloc):

```
UI (StatefulWidget screens)
      │
      ▼
Stateless service classes (static methods)
      │
      ├── DetectorService      → on-device object detection (TFLite) + iOS Vision segmentation
      ├── DictionaryService    → bundled JSON dictionary lookups
      ├── FirestoreService     → all Firestore reads/writes (words, streaks, friends, progress)
      ├── TtsService           → text-to-speech playback
      └── Firebase SDKs        → Auth, Firestore, Storage, AI (Gemini), App Check
```

- **No routing package** — navigation is done with `Navigator.push(MaterialPageRoute(...))` and a custom `TabSwitcher`/`InheritedWidget` for bottom-nav tab switching (see `main.dart`).
- **Theming** is centralized in `app_theme.dart` via a `ThemeNotifier` (`ChangeNotifier`) exposed through an `InheritedWidget` (`ThemeProvider`), persisted to `SharedPreferences` (dark/light mode).
- **Auth gating**: `auth/auth_gate.dart` decides between `login_screen.dart` / `signup_screen.dart` and the main app shell based on Firebase Auth state.
- Business logic largely lives as **static methods on service classes** (`DetectorService`, `DictionaryService`, `FirestoreService`) rather than injected dependencies — simple and pragmatic for an app this size, but means most services are effectively global singletons.

---

## 3. Screens / Feature Modules (`lib/`)

| File                                                                                                                                 | Responsibility                                                                                                            |
| ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `main.dart`                                                                                                                          | App bootstrap, Firebase init, theme + tab-switch plumbing                                                                 |
| `auth/auth_gate.dart`, `login_screen.dart`, `signup_screen.dart`                                                                     | Firebase Auth email/password flow                                                                                         |
| `home_screen.dart`                                                                                                                   | Main landing/dashboard, bottom navigation shell                                                                           |
| `live_scanner_tab.dart`                                                                                                              | Camera live-scan flow: image stream → detection stabilization → cutout capture → mascot feedback → hands off to AR screen |
| `ar_anchor_screen.dart`                                                                                                              | ARKit camera passthrough (`arkit_plugin`) with a floating word/definition card and cutout image overlay                   |
| `camera_word_panel.dart`                                                                                                             | Bottom-sheet style word detail panel (word, phonetic, definitions, example, actions)                                      |
| `topic_capture_screen.dart`                                                                                                          | Guided "find this object" capture flow for topic-based lessons, with instruction card + target frame overlay              |
| `topics_screen.dart`, `topics_data.dart`, `topic_word_grid_screen.dart`, `topic_complete_screen.dart`, `topics_complete_screen.dart` | Topic catalogue (data-driven via `kTopics`), per-topic word grids, completion screens                                     |
| `vocab_detail_screen.dart`                                                                                                           | Detailed view of a single learned/saved word                                                                              |
| `flashcard_screen.dart`                                                                                                              | Flashcard-style review of saved words                                                                                     |
| `quiz_screen.dart`                                                                                                                   | Quiz/testing mode over vocabulary                                                                                         |
| `review_screen.dart`                                                                                                                 | Spaced review / streak-driven revision                                                                                    |
| `saved_screen.dart`                                                                                                                  | List of the user's saved words                                                                                            |
| `gobot_screen.dart`                                                                                                                  | Gemini-powered AI chat companion ("Gobot")                                                                                |
| `event_screen.dart`, `event_group_lobby_screen.dart`, `event_gameplay_screen.dart`, `event_invites_screen.dart`                      | Multiplayer/group vocabulary game events + invites                                                                        |
| `friends_screen.dart`, `friend_profile_screen.dart`                                                                                  | Friends list & social profiles                                                                                            |
| `profile_screen.dart`, `edit_profile_screen.dart`                                                                                    | User profile view/edit                                                                                                    |
| `app_theme.dart`                                                                                                                     | Design tokens (colors, light/dark themes), `ThemeNotifier`, bottom-nav item definitions                                   |
| `firebase_options.dart`                                                                                                              | Auto-generated FlutterFire platform config                                                                                |

### Core services

- **`detector_service.dart`** — Loads a custom Ultralytics YOLO model (`assets/Models/best.tflite`, 60/118-class variants seen in training config) via `tflite_flutter`. Decodes the raw `[1, 4+classes, anchors]` output manually (no NMS needed since only the top-1 detection is used), handles both camera-stream frames (BGRA8888/YUV420) and static images, applies letterbox preprocessing, and calls a native iOS **MethodChannel** (`hololingo/vision`) for Apple Vision-based foreground/background segmentation to produce a transparent cutout PNG of the detected object.
- **`dictionary_service.dart`** — Looks up word metadata from the bundled `assets/dictionary/<letter>/<word>.json` files (sourced from the open-source "Open Dictionary" project, ~260k+ English words from Wiktionary — vendored under `open-dictionary/`).
- **`firestore_service.dart`** — All Firestore access: saved words, scan history, chat history, streaks, progress, topic progress, friends/friend requests/friendships, "bonds". Enforces per-user data ownership at the query layer (mirrored by `firestore.rules`).
- **`tts_service.dart`** + inline `flutter_tts` usage — Pronounces detected/reviewed words (`en-US`, iOS playback audio category configured for speaker + Bluetooth).

---

## 4. Client-Side "AI"/ML Pipeline

1. **Object detection**: custom-trained YOLO model (Ultralytics export), TFLite format, run fully on-device via `tflite_flutter`. Training config (`training/data.yaml`) lists up to 118 classes (everyday objects, animals, vehicles, electronics, etc.), sourced/versioned through **Roboflow** (project `hololingo`, workspace `may-thet-htar-lwin`).
2. **Background/foreground segmentation**: not a Flutter/Dart model — delegated to **Apple's Vision framework** natively on iOS through a `MethodChannel`, since true instance segmentation isn't done by the YOLO model.
3. **Conversational AI**: `gobot_screen.dart` uses **Firebase AI Logic** (`firebase_ai` package) to call **Gemini** (`gemini-3.7-flash`) directly from the client for the Gobot chat companion — no custom backend proxy.

---

## 5. Backend / Cloud (Firebase)

Configured via `firebase.json` / `firebase_options.dart`, using:

- **Firebase Auth** — email/password sign-in.
- **Cloud Firestore** — primary data store. Rules (`firestore.rules`) scope nearly everything to `request.auth.uid`, with subcollections per user: `saved_words`, `chat_history`, `streak`, `progress`, `topic_progress`, `friends`; plus top-level `friend_requests`, `friendships`, `bonds`, and a read-only `config` collection. Indexes defined in `firestore.indexes.json`.
- **Firebase Storage** — asset/media storage (`firebase_storage` dependency).
- **Firebase AI Logic** — Gemini access for Gobot.
- **App Check** — present in dependency tree (Pods show `FirebaseAppCheck`/`AppCheckCore`) for local iOS dev/testing attestation.
- **In-App Purchase** (`in_app_purchase`) — monetization hooks (topics have an `isPremium` flag in `topics_data.dart`).

There is **no custom backend server** — the Flutter client talks directly to Firebase and (for the dictionary) to a bundled offline JSON dataset, not a live API.

---

## 6. Key Dependencies (`pubspec.yaml`)

| Package                                                                                | Purpose                                                                                                                                          |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_ai` | Firebase platform + Gemini AI                                                                                                                    |
| `in_app_purchase`                                                                      | Premium topic purchases                                                                                                                          |
| `camera`                                                                               | Live camera preview + image stream capture                                                                                                       |
| `arkit_plugin`                                                                         | iOS ARKit camera scene / AR overlay screen                                                                                                       |
| `tflite_flutter`                                                                       | On-device YOLO inference                                                                                                                         |
| `image`                                                                                | Pixel-level image processing (letterboxing, cropping, PNG encode/decode, and — added recently — mascot asset background-removal/trim processing) |
| `flutter_tts`                                                                          | Text-to-speech                                                                                                                                   |
| `sensors_plus`                                                                         | Accelerometer input (mascot tilt/parallax effect)                                                                                                |
| `path_provider`                                                                        | Local file storage for captured frames/cutouts                                                                                                   |
| `shared_preferences`                                                                   | Persisted theme preference                                                                                                                       |
| `share_plus`, `image_picker`                                                           | Sharing + manual image selection                                                                                                                 |
| `http`, `vector_math`                                                                  | Networking utility / AR math                                                                                                                     |
| `flutter_launcher_icons` (dev)                                                         | App icon generation from `assets/hololingo.png`                                                                                                  |

Platform targets present: iOS (primary, CocoaPods-managed under `ios/Pods`), Android, macOS, Linux, Windows, Web (standard Flutter multi-platform scaffolding, though ARKit/Vision/TFLite features are iOS-centric).

---

## 7. Assets & Data

- `assets/Models/best.tflite`, `assets/detect.tflite` — object detection models.
- `assets/dictionary/{a..z}/*.json` + `valid_words.json` — offline English dictionary (vendored from `open-dictionary/`, ~260k words, MIT/Wiktionary-sourced).
- `assets/hololingo.png`, `assets/gobot.png` — branding/launcher icon + nav icon.
- `assets/mascot/` — flat mood illustrations (`thinking.png`, `confused.png`, `congrats.png`, `pointing.png`) — legacy, currently unused after the rig rewrite.
- `assets/mascot/parts/` — layered mascot rig parts (`body`, `head`, `face`, `antenna_left/right`, `arm_left/right`, `hand_left/right`, `leg_left/right`, `question_mark`, `accent`) used to animate the live-scanner mascot as an independently-posed puzzle rig (custom asset post-processing trims transparent padding and removes flat-white backgrounds at runtime, see `_MascotAssets` in `live_scanner_tab.dart`).
- `training/` — YOLO dataset config (`data.yaml`) and test data for the custom Roboflow-trained detector.
- `open-dictionary/` — vendored copy of the third-party "Open Dictionary" project (JSON API + demo site) used as the data source for `assets/dictionary`.

---

## 8. Notable In-App Systems Worth Calling Out

- **Live scanner mascot** (`live_scanner_tab.dart`): a hand-built animated companion reacting to scan state —
  - `thinking` while scanning, `sad` if detections keep flip-flopping (phone/object moving too much) or after a failed scan, `happy`/`pointing` once a word is confidently detected (3 stable detections in a row within a 3s window).
  - Rendered as a **jointed rig** (`_MascotRig`) composited from the separate part PNGs, each independently rotated/animated (per-mood pose table in `_MascotPose`), plus a continuous idle float, phone-tilt-driven parallax (via `sensors_plus` accelerometer stream), and a fake-3D perspective transform (`Matrix4` rotateX/rotateY) — all without needing true 3D assets.
- **Detection stabilization**: requires the same label to be seen 3 times before accepting it, to avoid false positives from a single noisy frame.
- **Silent capture**: uses the live camera image stream + manual JPEG encode instead of `controller.takePicture()`, avoiding the OS shutter sound so scanning feels continuous rather than a discrete "photo" action.

---

## 9. Data Accuracy

Hololingo is a learning tool, so a wrong answer costs more than a missing one: if the app labels a mug as a "vase", the learner memorises the wrong word. The app therefore checks accuracy at three points: recognising the object, finding the word's meaning, and recording the learner's progress. In each case it would rather say "not sure" than show something wrong.

### 9.1 Object recognition

**Model and dataset.** Detection uses a custom YOLO model (`assets/Models/best.tflite`, 640×640 input) trained on 135 everyday-object classes from the team's Roboflow dataset (`hololingo-piu7w`, version 2, CC BY 4.0; config in `training/data64k.yaml`). Inference runs entirely on-device.

> **Training metrics — to be filled in from the final training run:** mAP@50 = ___, mAP@50-95 = ___, precision = ___, recall = ___ (validation split). Also note any classes with clearly weaker results.

**Confidence threshold.** A detection is accepted only if its confidence score reaches the minimum threshold (`DetectorService._confidenceThreshold`, currently **0.08**). The threshold looks low because the merged 135-class model gives lower scores overall than the earlier 89-class model, even for objects it identifies correctly (a clearly framed laptop scored about 0.12–0.15, for example). A higher threshold rejected too many correct detections. The threshold alone doesn't protect accuracy; the checks below do most of that work.

**Agreement across frames (live scanner).** The live scanner never accepts a label from a single camera frame. A word is accepted only after the model returns the **same label in 3 frames** (`_requiredStableDetections = 3`). Usually, one blurry or badly angled frame can't produce a result on its own. A scan lasts up to 3 seconds. If no label reaches 3 frames by then, the scanner uses the label it saw most often (see 9.4). If it saw nothing, it asks the learner to aim again. Labels that aren't useful vocabulary targets (`person`, `human`, `background`, `unknown`) are ignored.

**Target-checked capture (topic lessons).** In guided topic lessons, the learner is asked to find a specific object. The detector only accepts classes that match that target (with a few deliberate equivalents: a laptop seen from some angles is classified as `computer-monitor` or `notebook`). If nothing matching is found, the app retries the capture **once** to recover from a single bad frame, and then reports *"No object was detected clearly"*. It **never falls back to the target word** when nothing was detected. Doing so would mark an unrelated object as correct. The confidence score is shown to the learner on the result card.

**Label integrity.** The app doesn't read the dataset's YAML at runtime; the class names are compiled into `DetectorService` in class-index order. At load time the app checks that the number of labels matches the number of classes the model outputs. If they differ (for example, the model was retrained but the label list wasn't updated), detection is **disabled** rather than allowed to show the wrong names. The app's label list also corrects spelling mistakes in the training data's class names (`Cabel` → *cable*, `Grasshoper` → *grasshopper*), so learners never see the misspellings.

### 9.2 Word and definition accuracy

Detector class names don't always match dictionary headwords. `DictionaryService.normalizeWord` maps the problem labels to real words (`computer-monitor` → *monitor*, `stop-sign` → *sign*, `potted plant` → *plant*, and so on). Each mapping was checked against the bundled dictionary files before it was added.

Definitions are looked up in a fixed order of trust:

1. **Curated entries.** Hand-written definitions, phonetics and example sentences for the app's core vocabulary.
2. **Bundled offline dictionary.** Open Dictionary (Wiktionary-derived, about 260k words), under `assets/dictionary/`.
3. **Online dictionary** (`dictionaryapi.dev`). Supplies phonetics, which the offline data never includes, and acts as a last resort for words missing offline. "Not found" answers are cached so the app doesn't keep asking.
4. **Honest placeholder.** If all of these fail, the app says the definition isn't available yet. It does **not** generate or guess one.

### 9.3 Learner progress and game data

Progress data such as XP, review counts and challenge scores is stored in Cloud Firestore. It is written so that two updates at the same moment can't overwrite each other:

- **Atomic counters.** XP, words saved, scan counts and times reviewed use `FieldValue.increment`, so updates from two devices at once are both counted.
- **Transactions.** Spaced-review state (`correct_count`, `wrong_count`, `review_stage`) and Daily Challenge rounds are updated inside Firestore transactions. Each update reads and writes the data in a single step, so no change is lost.
- **Server timestamps.** All times are set by the Firestore server (`FieldValue.serverTimestamp()`), not the phone's clock. This matters most for the Daily Challenge, where *the first correct answer wins* is decided by server timestamp. A player can't win by setting their phone clock back.
- **Ownership rules.** `firestore.rules` only lets each user write their own data, so one user can't change another user's progress.

### 9.4 Limitations

- There is no automated test that measures real-world recognition accuracy. Accuracy has been checked by hand on real objects, and the confidence threshold was set by testing on devices.
- The low threshold relies on the 3-frame check in the live scanner. That check doesn't apply when the 3-second scan ends without any label reaching 3 frames: the scanner then uses the most frequent label, which could have been seen in just one frame. Requiring at least 2 matching frames in that case would close this gap. Topic capture uses a single frame plus one retry, so a wrong label is more likely there. Restricting detection to the target class reduces this risk.
- Accuracy varies between classes. Visually similar objects (laptop vs monitor, cup vs mug vs paper cup, sofa vs couch) are the most common mix-ups.
- Online phonetics need a network connection. Offline, some words appear without pronunciation guides.

---

## 10. Known Rough Edges / Things to Check

- `README.md` currently contains **unresolved git merge-conflict markers** (`<<<<<<< HEAD` / `=======` / `>>>>>>>`) — should be cleaned up.
- The four flat `assets/mascot/*.png` mood images are now dead weight (superseded by `assets/mascot/parts/`) — safe to remove if no longer needed, or keep as a documented fallback.
- No automated test coverage beyond the default `test/widget_test.dart` scaffold.
- No formal state-management library — fine at current size, but growth (event/social/gameplay features) may benefit from one as the app scales.
