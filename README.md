# Mindrove Miniprojekt (MineRove)

Small Godot games controlled with hand gestures, read from a **MindRove EMG armband**.
The band measures muscle activity in the forearm, a classifier turns it into gestures
(fist, open hand, wrist left/right, ...), and the games use those gestures as input.

All games also work with the arrow keys, for testing without the band.

## Requirements

- Godot 4.4 or newer (the project is made with 4.7) 
- Linux x86_64 (the native library in `bin/` is built for Linux) can be build for window but i dont want to
- A MindRove armband on the same WiFi

## How it works

The EMG part is a C++ GDExtension (`bin/libminerove.*.so`) that wraps the MindRove SDK:

| Class | What it does |
| --- | --- |
| `EmgBand` | Connects to the band and streams EMG, accelerometer and gyro data |
| `HudginsFeatures` | Turns raw EMG into features (Hudgins time-domain features) |
| `LdaClassifier`, `SvmClassifier` | Classify the features into gestures |
| `GestureRecognizer` | Records calibration data, trains the classifier, outputs the smoothed gesture and force |

## Rebuilding the C++ extension

The C++ source (`src/`, `SConstruct`, `godot-cpp`, MindRove SDK) is not in this repo yet.
In that folder, build with:

```bash
scons compiledb=yes
```

The output goes to `bin/` here.

## Credits (need to be here or else we get shit)

- Multiplayer lobby code based on [Godot Steam & Local Multiplayer Lobby Template](https://github.com/ViMayer/Godot-Steam-Local-Multiplayer-Lobby-Template) by Victor Mayer (MIT)
- [GodotSteam](https://codeberg.org/godotsteam/godotsteam)
- [MindRove](https://mindrove.com) SDK
