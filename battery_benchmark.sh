#!/bin/bash

set -m

show_help() {
cat <<-EOF

macOS "Real-Work" Battery Benchmark Script

Usage:
  ./battery_benchmark.sh [options]

Options:
  --xcode PATH       (Optional) The absolute path to an .xcodeproj or .xcworkspace
                     to include in the benchmark. This adds a heavy IDE build
                     loop to the workload.

  --mode MODE        (Optional) Workload intensity: light, medium, heavy
                     Default: medium

  --log-interval SEC (Optional) Battery logging interval in seconds
                     Default: 60

  --no-safari        (Optional) Skip Safari automation

  --target-percent N (Optional) Stop test when battery reaches N%
                     Default: run until stopped manually

  -h, --help         Show this help manual and exit.

Description:
  This script runs a "real-world" developer workload to benchmark
  Mac battery life. It logs battery percentage, power state, and time
  remaining to a CSV file every 60 seconds.

  The workload includes:
  - Caffeinate (prevents sleep)
  - Safari (reloads 4 developer sites every 30s) - optional
  - CPU (compresses random data) - intensity varies by mode
  - Disk I/O (makes constant, small Git commits)
  - Xcode (constant clean/build loop, if path is provided)

  Workload Modes:
  - light:  Minimal CPU usage, simulates reading/light browsing
  - medium: Moderate activity, typical development work (default)
  - heavy:  Maximum load, stress test scenario

How to Run:
  1. Make the script executable:
     chmod +x battery_benchmark.sh

  2. Run (Lite workload, no Xcode):
     ./battery_benchmark.sh

  3. Run (Full workload, with Xcode):
     ./battery_benchmark.sh --xcode "/Users/yourname/Projects/MyAwesomeApp"

  4. Run (Heavy mode, stop at 20%):
     ./battery_benchmark.sh --mode heavy --target-percent 20

  5. Run (Light mode, no Safari, 5min logging):
     ./battery_benchmark.sh --mode light --no-safari --log-interval 300

  6. Stop the test:
     Press CTRL+C

Output:
  A log file named 'battery_log_YYYYMMDD_HHMM.csv' will be created
  in the current directory.

EOF
}

###############################################################################
# Argument Parsing
###############################################################################

# Set default
PROJECT_PATH=""
WORKLOAD_MODE="medium"
LOG_INTERVAL=60
SKIP_SAFARI=false
TARGET_PERCENT=""

# Loop through arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            # Show the help manual
            show_help
            exit 0
            ;;
        --xcode)
            # Check if a path was provided after the flag
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                PROJECT_PATH="$2"
                shift # past flag
                shift # past value
            else
                echo "ERROR: Argument for --xcode is missing" >&2
                exit 1
            fi
            ;;
        --mode)
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                WORKLOAD_MODE="$2"
                if [[ ! "$WORKLOAD_MODE" =~ ^(light|medium|heavy)$ ]]; then
                    echo "ERROR: --mode must be light, medium, or heavy" >&2
                    exit 1
                fi
                shift
                shift
            else
                echo "ERROR: Argument for --mode is missing" >&2
                exit 1
            fi
            ;;
        --log-interval)
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                LOG_INTERVAL="$2"
                if ! [[ "$LOG_INTERVAL" =~ ^[0-9]+$ ]] || [ "$LOG_INTERVAL" -lt 1 ]; then
                    echo "ERROR: --log-interval must be a positive number" >&2
                    exit 1
                fi
                shift
                shift
            else
                echo "ERROR: Argument for --log-interval is missing" >&2
                exit 1
            fi
            ;;
        --no-safari)
            SKIP_SAFARI=true
            shift
            ;;
        --target-percent)
            if [ -n "$2" ] && [[ "$2" != -* ]]; then
                TARGET_PERCENT="$2"
                if ! [[ "$TARGET_PERCENT" =~ ^[0-9]+$ ]] || [ "$TARGET_PERCENT" -lt 1 ] || [ "$TARGET_PERCENT" -gt 100 ]; then
                    echo "ERROR: --target-percent must be a number between 1 and 100" >&2
                    exit 1
                fi
                shift
                shift
            else
                echo "ERROR: Argument for --target-percent is missing" >&2
                exit 1
            fi
            ;;
        *)
            # Unknown option: Print error and list known options
            echo "ERROR: Unknown option: $1" >&2
            echo ""
            echo "Known options are:"
            echo "  --xcode PATH         [Optional] Path to an Xcode project."
            echo "  --mode MODE          [Optional] Workload mode: light, medium, heavy"
            echo "  --log-interval SEC   [Optional] Battery logging interval"
            echo "  --no-safari          [Optional] Skip Safari automation"
            echo "  --target-percent N   [Optional] Stop at battery N%"
            echo "  -h, --help           [Optional] Show the help manual."
            echo ""
            echo "Run with -h or --help for more details."
            exit 1
            ;;
    esac
done

#############################################################################
# Cleanup handler
#############################################################################

# Track PIDs globally
CAFFEINATE_PID=""
SAFARI_REFRESH_PID=""
XCODE_PID=""
CPU_TASK_PID=""
GIT_TASK_PID=""
BATTERY_LOG_PID=""
TEMP_REPO=""

MAIN_PID=$$
export MAIN_PID

cancel() {
  # Clear the trap to prevent this function from running twice
  trap - INT TERM

  echo ""
  echo "Stopping workload..."

  # Helper to gracefully then forcefully kill a process group
  kill_group() {
    local PID="$1"
    if [[ -n "$PID" ]]; then
      # Send SIGTERM to the process group first
      kill -TERM -"$PID" 2>/dev/null
      sleep 0.5
      # If anything is still around, send SIGKILL to the group
      kill -KILL -"$PID" 2>/dev/null
    fi
  }

  echo "Killing background jobs..."
  kill_group "$SAFARI_REFRESH_PID"
  kill_group "$XCODE_PID"
  kill_group "$CPU_TASK_PID"
  kill_group "$GIT_TASK_PID"
  kill_group "$BATTERY_LOG_PID"
  kill_group "$CAFFEINATE_PID"

  # Wait a moment for processes to terminate
  sleep 1

  # Remove temp repo
  if [[ -n "$TEMP_REPO" ]] && [[ -d "$TEMP_REPO" ]]; then
      rm -rf "$TEMP_REPO"
      echo "Removed temporary repository: $TEMP_REPO"
  fi

  # Generate summary statistics
  generate_summary

  echo "# Test finished at $(date)" >> "$LOGFILE"
  echo "Cleanup complete. Exiting."

  exit 0
}

trap cancel INT TERM

###############################################################################
# Summary Statistics Function
###############################################################################

generate_summary() {
  if [[ ! -f "$LOGFILE" ]]; then
    return
  fi

  echo ""
  echo "========================================="
  echo "Battery Test Summary"
  echo "========================================="
  echo "System: $MODEL_NAME ($CHIP_NAME, $MEMORY_SIZE RAM)"
  echo "OS:     $OS_FULL"
  echo "========================================="
  
  # Extract data lines (skip comments)
  DATA=$(grep -v "^#" "$LOGFILE" | tail -n +2)
  
  if [[ -z "$DATA" ]]; then
    echo "No data collected."
    return
  fi
  
  FIRST_LINE=$(echo "$DATA" | head -n 1)
  LAST_LINE=$(echo "$DATA" | tail -n 1)
  
  START_PCT=$(echo "$FIRST_LINE" | cut -d',' -f2)
  END_PCT=$(echo "$LAST_LINE" | cut -d',' -f2)
  START_TIME=$(echo "$FIRST_LINE" | cut -d',' -f1)
  END_TIME=$(echo "$LAST_LINE" | cut -d',' -f1)
  
  # Calculate duration
  START_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME" "+%s" 2>/dev/null)
  END_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$END_TIME" "+%s" 2>/dev/null)
  
  if [[ -n "$START_EPOCH" ]] && [[ -n "$END_EPOCH" ]]; then
    DURATION_SEC=$((END_EPOCH - START_EPOCH))
    DURATION_MIN=$((DURATION_SEC / 60))
    DURATION_HR=$(echo "scale=2; $DURATION_MIN / 60" | bc)
    
    echo "Start Time:      $START_TIME"
    echo "End Time:        $END_TIME"
    echo "Duration:        ${DURATION_HR} hours (${DURATION_MIN} minutes)"
    echo "Start Battery:   ${START_PCT}%"
    echo "End Battery:     ${END_PCT}%"
    
    if [[ "$START_PCT" -gt "$END_PCT" ]]; then
      DRAIN=$((START_PCT - END_PCT))
      echo "Battery Drain:   ${DRAIN}%"
      
      if [[ $DRAIN -gt 0 ]] && [[ $DURATION_MIN -gt 0 ]]; then
        DRAIN_RATE_PER_MIN=$(echo "scale=4; $DRAIN / $DURATION_MIN" | bc)
        DRAIN_RATE_PER_HOUR=$(echo "scale=2; $DRAIN_RATE_PER_MIN * 60" | bc)
        ESTIMATED_LIFE=$(echo "scale=2; 100 / $DRAIN_RATE_PER_HOUR" | bc)
        echo "Drain Rate:      ${DRAIN_RATE_PER_HOUR}% per hour"
        echo "Est. Full Life:  ${ESTIMATED_LIFE} hours"
      fi
    fi
    
    echo "Workload Mode:   $WORKLOAD_MODE"
    echo "Log File:        $LOGFILE"
  fi
  
  echo "========================================="
}

###############################################################################
# Full-Day Real-Work Simulation Battery Life Test (CSV logging, enhanced)
###############################################################################

LOGFILE="battery_log_$(date +"%Y%m%d_%H%M").csv"

# Gather System Information
echo "Gathering system information..."

# Check if device has a battery
if ! pmset -g batt | grep -q "InternalBattery"; then
  echo "----------------------------------------------------------------"
  echo "❌ ERROR: No internal battery detected."
  echo "   This script is designed for MacBooks."
  echo "   Running on a desktop Mac (iMac, Mac Studio, etc.) is not supported."
  echo "----------------------------------------------------------------"
  exit 1
fi

# 1. OS Name & Version (e.g., "macOS 15.1")
OS_NAME=$(sw_vers -productName)
OS_VER=$(sw_vers -productVersion)
OS_BUILD=$(sw_vers -buildVersion)
OS_FULL="$OS_NAME $OS_VER ($OS_BUILD)"

# 2. Model Name (e.g., "MacBook Pro")
# We use sysctl for a cleaner model identifier, or system_profiler for the marketing name.
# system_profiler is slower but gives the nice name like "MacBook Pro (14-inch, Nov 2023)"
MODEL_NAME=$(system_profiler SPHardwareDataType | grep "Model Name" | awk -F': ' '{print $2}' | xargs)
MODEL_ID=$(system_profiler SPHardwareDataType | grep "Model Identifier" | awk -F': ' '{print $2}' | xargs)
CHIP_NAME=$(system_profiler SPHardwareDataType | grep "Chip" | awk -F': ' '{print $2}' | xargs)

# Fallback for Intel Macs which list "Processor Name" instead of "Chip"
if [[ -z "$CHIP_NAME" ]]; then
  CHIP_NAME=$(system_profiler SPHardwareDataType | grep "Processor Name" | awk -F': ' '{print $2}' | xargs)
fi

# 3. CPU Cores
CORE_COUNT=$(system_profiler SPHardwareDataType | grep "Total Number of Cores" | awk -F': ' '{print $2}' | xargs)

# 4. RAM
MEMORY_SIZE=$(system_profiler SPHardwareDataType | grep "Memory" | awk -F': ' '{print $2}' | xargs)

# 5. Disk Capacity (System Drive)
# We use df -h / to get the readable size of the main disk
DISK_SIZE=$(df -h / | awk 'NR==2 {print $2}')

echo "Starting Battery Benchmark Test..."
echo "Workload Mode: $WORKLOAD_MODE"
echo "CSV log file: $LOGFILE"

# CSV header + Metadata
{
  echo "# Battery Benchmark Test"
  echo "# Started: $(date)"
  echo "# --------------------------------------"
  echo "# System Information:"
  echo "# Model:   $MODEL_NAME ($MODEL_ID)"
  echo "# OS:      $OS_FULL"
  echo "# Chip:    $CHIP_NAME"
  echo "# Cores:   $CORE_COUNT"
  echo "# RAM:     $MEMORY_SIZE"
  echo "# Disk:    $DISK_SIZE (System Volume)"
  echo "# --------------------------------------"
  echo "# Test Settings:"
  echo "# Mode:    $WORKLOAD_MODE"
  [[ -n "$TARGET_PERCENT" ]] && echo "# Target: Stop at ${TARGET_PERCENT}%"
  echo "# Log Interval: ${LOG_INTERVAL}s"
  echo "timestamp,battery_percent,power_state,time_remaining"
} > "$LOGFILE"

# Prevent system sleep
caffeinate -dimsu &
CAFFEINATE_PID=$!
echo "Started caffeinate (PID: $CAFFEINATE_PID)"

###############################################################################
# Safari automation
###############################################################################

if [ "$SKIP_SAFARI" = false ]; then
  /usr/bin/open -a "Safari" "https://news.ycombinator.com/"
  /usr/bin/open -a "Safari" "https://stackoverflow.com/questions"
  /usr/bin/open -a "Safari" "https://github.com/trending"
  /usr/bin/open -a "Safari" "https://developer.apple.com/documentation"

  (
    while true; do
      osascript <<EOF
        tell application "Safari"
          if (count of windows) > 0 then
            repeat with t in tabs of front window
              try
                set URL of t to (URL of t)
              end try
            end repeat
          end if
        end tell
EOF
      sleep 30
    done
  ) &
  SAFARI_REFRESH_PID=$!
  echo "Started Safari refresh loop (PID: $SAFARI_REFRESH_PID)"
else
  echo "Skipping Safari automation (--no-safari)"
fi

###############################################################################
# 1. Xcode build loop (update path!)
###############################################################################
if [ -d "$PROJECT_PATH" ]; then
  (
    while true; do
      cd "$PROJECT_PATH"
      xcodebuild clean > /dev/null 2>&1
      xcodebuild build -configuration Release > /dev/null 2>&1
    done
  ) &
  XCODE_PID=$!
  echo "Started Xcode build loop (PID: $XCODE_PID)"
fi

###############################################################################
# 2. CPU workload (varies by mode)
###############################################################################
case $WORKLOAD_MODE in
  light)
    # Light: Small bursts, lots of sleep
    (
      while true; do
        dd if=/dev/urandom bs=1m count=10 2>/dev/null | gzip > /dev/null
        sleep 30
      done
    ) &
    CPU_TASK_PID=$!
    echo "Started LIGHT CPU workload (PID: $CPU_TASK_PID)"
    ;;
    
  medium)
    # Medium: Moderate continuous load
    (
      while true; do
        dd if=/dev/urandom bs=1m count=50 2>/dev/null | gzip > /dev/null
      done
    ) &
    CPU_TASK_PID=$!
    echo "Started MEDIUM CPU workload (PID: $CPU_TASK_PID)"
    ;;
    
  heavy)
    # Heavy: Multiple parallel compression tasks
    (
      while true; do
        dd if=/dev/urandom bs=1m count=100 2>/dev/null | gzip > /dev/null &
        dd if=/dev/urandom bs=1m count=100 2>/dev/null | gzip > /dev/null &
        wait
      done
    ) &
    CPU_TASK_PID=$!
    echo "Started HEAVY CPU workload (PID: $CPU_TASK_PID)"
    ;;
esac

###############################################################################
# 3. Git workload
###############################################################################
TEMP_REPO=$(mktemp -d)
echo "Created temporary repository: $TEMP_REPO"
(
  cd "$TEMP_REPO"
  git init > /dev/null 2>&1
  touch file.txt
  git add .
  git commit -m "Initial" > /dev/null 2>&1
  
  while true; do
    echo "$(date)" >> file.txt
    git add file.txt
    git commit -m "Update $(date)" > /dev/null 2>&1
    git gc --aggressive > /dev/null 2>&1
    sleep 20
  done
) &
GIT_TASK_PID=$!
echo "Started Git workload (PID: $GIT_TASK_PID)"

###############################################################################
# 4. Battery logging in CSV format (Robust Version)
###############################################################################
(
  while true; do
    RAW=$(pmset -g batt | grep "%")

    # Detect sudden disappearance of battery info (shutdown or critical)
    if [[ -z "$RAW" ]]; then
      echo "$(date "+%Y-%m-%d %H:%M:%S"),0,shutdown," >> "$LOGFILE"
      break
    fi

    # 1. Parse Percentage: Find digits before '%'
    PCT=$(echo "$RAW" | grep -o "[0-9]*%" | tr -d '%')

    # 2. Parse State: Get text between 1st and 2nd semicolon
    STATE=$(echo "$RAW" | awk -F';' '{print $2}' | xargs)

    # 3. Parse Remaining: Get text after 2nd semicolon
    # This produces something like "12:12 remaining present: true"
    REMAIN_FULL=$(echo "$RAW" | awk -F';' '{print $3}' | xargs)

    if [[ "$REMAIN_FULL" == *"(no estimate)"* ]]; then
      REMAIN="(no estimate)"
    else
      # Take only the first word (the time, e.g., "12:12")
      REMAIN=$(echo "$REMAIN_FULL" | awk '{print $1}')
    fi

    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Only log valid entries
    if [ -n "$PCT" ] && [ -n "$STATE" ]; then
      echo "$TIMESTAMP,$PCT,$STATE,$REMAIN" >> "$LOGFILE"

      # Check target percent
      if [[ -n "$TARGET_PERCENT" ]] && [[ "$PCT" -le "$TARGET_PERCENT" ]]; then
        echo "Target battery level ${TARGET_PERCENT}% reached (current: ${PCT}%)"
        kill -INT "$MAIN_PID"
        break
      fi
    fi

    sleep "$LOG_INTERVAL"
  done
) &
BATTERY_LOG_PID=$!
echo "Started battery logger (PID: $BATTERY_LOG_PID, interval: ${LOG_INTERVAL}s)"
[[ -n "$TARGET_PERCENT" ]] && echo "Will stop automatically at ${TARGET_PERCENT}% battery"

###############################################################################
# Main
###############################################################################
echo ""
echo "Workload running. Unplug your charger now."
echo "Press CTRL+C to stop early."
echo ""

# Pause the script here, waiting for background jobs to end.
# Our 'trap' will catch Ctrl+C, run cancel(),
# which kills all jobs, causing 'wait' to exit.
wait
