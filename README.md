# Mindrove Miniprojekt (MineRove)

Small Godot games controlled with hand gestures, read from a **MindRove EMG armband**.
The band measures muscle activity in the forearm, a classifier turns it into gestures
(fist, open hand, wrist left/right, ...), and the games use those gestures as input.

## Games

- **EMG Race**: 3D racing. Gas, brake and steering are gestures; the harder you hold a gesture, the stronger it acts.
- **Target Reach**: steer a dot onto targets on a ring and hold it there.
- **Versus (LAN)**: host or join a match on the local network and play the games against each other, each player on their own PC with their own band.

All games also work with the arrow keys, for testing without the band.

## Requirements

- Godot 4.4 or newer (the project is made with 4.7)
- Linux x86_64 (the native library in `bin/` is built for Linux)
- A MindRove armband on the same WiFi, or the synthetic board for testing without one

## Getting started

1. Clone the repo and open the folder in Godot (**Import**, select `project.godot`).
2. Run the project. The main menu shows the games and a **Calibrate** button.
3. Connect to the band's WiFi, open **Calibrate** and follow the steps:
   1. Hold each gesture normally a few times (trains the classifier).
   2. Hold each gesture as hard as you can (sets 100% force).
   3. Hold each gesture on the 50% line on the force graph.

   The model is saved to `user://gesture_model.json` and loaded automatically on the next start.
4. Pick a game.

## How it works

The EMG part is a C++ GDExtension (`bin/libminerove.*.so`) that wraps the MindRove SDK:

| Class | What it does |
| --- | --- |
| `EmgBand` | Connects to the band and streams EMG, accelerometer and gyro data |
| `HudginsFeatures` | Turns raw EMG into features (Hudgins time-domain features) |
| `LdaClassifier`, `SvmClassifier` | Classify the features into gestures |
| `GestureRecognizer` | Records calibration data, trains the classifier, outputs the smoothed gesture and force |

The `Emg` autoload (`scripts/globals/emg_input.gd`) builds that chain and loads the saved model,
so a game only has to do:

```gdscript
Emg.gesture_changed.connect(_on_gesture)
if Emg.is_gesture("fist"):
    ...
```

Only one `EmgInput` / `EmgBand` can talk to the band at a time.

LAN multiplayer is handled by the `Online` and `Versus` autoloads.

## Project layout

```
scenes/
  calibration/   gesture calibration screen and live plots
  games/         race/ and target_reach/
  menus/         main menu and versus lobby
scripts/globals/ autoloads: Emg, Online, Versus
bin/             GDExtension + MindRove SDK libraries
addons/          GodotSteam, GDScript formatter
main.py          Python script that plots live EMG from the band
```

## Rebuilding the C++ extension

The C++ source (`src/`, `SConstruct`, `godot-cpp`, MindRove SDK) is not in this repo yet.
In that folder, build with:

```bash
scons compiledb=yes
```

The output goes to `bin/` here.

## Credits

- Multiplayer lobby code based on [Godot Steam & Local Multiplayer Lobby Template](https://github.com/ViMayer/Godot-Steam-Local-Multiplayer-Lobby-Template) by Victor Mayer (MIT)
- [GodotSteam](https://codeberg.org/godotsteam/godotsteam)
- [MindRove](https://mindrove.com) SDK
