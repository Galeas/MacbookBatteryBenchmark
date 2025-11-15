# macOS Battery Benchmark Script 🔋

A "real-world" battery benchmark tool designed for developers.

Unlike synthetic benchmarks that just pin the CPU at 100%, this script simulates a realistic **"Day in the Life"** workload. It automates web browsing, compilation, file I/O, and background tasks to measure how your MacBook battery performs under actual working conditions.



## 🚀 Features

* **Real-Work Simulation:** Mimics a developer workflow using Safari, Git, and standard system tools.
* **Dependency Free:** Written in pure Bash. No Python, Node, or third-party apps required.
* **Configurable Intensity:** Choose between `light`, `medium`, or `heavy` workload modes.
* **Xcode Support:** Optionally includes a continuous `xcodebuild` loop for heavy compiler testing.
* **Detailed Logging:** Generates a CSV file with timestamps, battery %, power state, and estimated time remaining.
* **Smart Safety:** Auto-detects hardware (won't run on desktops), prevents sleep via `caffeinate`, and cleans up all background processes on exit.

## 🛠️ Usage

### 1. Download & Permissions

Download the script and make it executable:

```bash
chmod +x battery_benchmark.sh
````

### 2\. Run the Benchmark

Unplug your charger and run the script.

**Standard Mode (Medium Intensity)**
Simulates typical web browsing and background tasks.

```bash
./battery_benchmark.sh
```

**Full Developer Mode (with Xcode)**
Adds a heavy compile loop. *Requires a valid path to an Xcode project.*

```bash
./battery_benchmark.sh --xcode "/Users/me/Projects/MyApp"
```

**Heavy Stress Test**
Runs multiple parallel CPU compression tasks.

```bash
./battery_benchmark.sh --mode heavy
```

**Targeted Run**
Run "Heavy" mode until the battery hits 20%, then stop automatically.

```bash
./battery_benchmark.sh --mode heavy --target-percent 20
```

### 3\. Stop the Test

Press `Ctrl+C` at any time. The script will automatically kill all background jobs, delete temporary files, and generate a summary report.

## 📊 Workload Modes

| Mode | CPU Load | Description |
| :--- | :--- | :--- |
| **Light** | Low | Simulates reading documentation, light browsing, and idle time. |
| **Medium** | Moderate | (Default) Simulates active development, constant web reloading, and background I/O. |
| **Heavy** | High | Stress test. Runs multiple parallel compression jobs and aggressive I/O. |

*All modes include Safari automation (reloading 4 tabs every 30s) and Git I/O unless disabled via `--no-safari`.*

## 📝 The Output Log

The script creates a CSV file in the current directory (e.g., `battery_log_20251115_1400.csv`). You can open this in Excel, Numbers, or Python for analysis.

**Example Output:**

```csv
timestamp,battery_percent,power_state,time_remaining
2025-11-15 14:00:01,98,discharging,10:23
2025-11-15 14:01:01,97,discharging,09:45
...
```

## ⚙️ Options

| Flag | Description |
| :--- | :--- |
| `--xcode PATH` | Path to an Xcode project/workspace to build repeatedly. |
| `--mode MODE` | Set intensity: `light`, `medium`, or `heavy` (Default: `medium`). |
| `--target-percent N` | Automatically stop the test when battery drops to N%. |
| `--no-safari` | Skip the browser automation loop. |
| `--log-interval SEC` | How often to write to the CSV log (Default: 60s). |

## 📄 License

MIT License. Feel free to modify and distribute as needed.
