#!/bin/bash

# Syncthing API endpoint
API_URL="http://localhost:8384/rest"
API_KEY_FILE="$HOME/.local/state/syncthing/config.xml"

# Extract API key from config
if [ -f "$API_KEY_FILE" ]; then
  API_KEY=$(grep -oP '(?<=<apikey>).*?(?=</apikey>)' "$API_KEY_FILE")
else
  echo '{"text": "󰯈", "tooltip": "Syncthing config not found", "class": "error"}'
  exit 1
fi

# Check if Syncthing is running
if ! pgrep -x "syncthing" >/dev/null; then
  echo '{"text": "󰯈", "tooltip": "Syncthing is not running", "class": "stopped"}'
  exit 0
fi

# Get system status
status_response=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL/system/status" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$status_response" ]; then
  echo '{"text": "󰯈", "tooltip": "Cannot connect to Syncthing API", "class": "error"}'
  exit 1
fi

# Parse status
syncing=$(echo "$status_response" | jq -r '.globalBytes // 0')
uptime=$(echo "$status_response" | jq -r '.uptime // 0')

# Get folder status
folders_response=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL/system/config" 2>/dev/null)
folder_count=0
sync_errors=0

if [ $? -eq 0 ] && [ -n "$folders_response" ]; then
  folder_count=$(echo "$folders_response" | jq -r '.folders | length')

  # Check for sync errors
  for folder_id in $(echo "$folders_response" | jq -r '.folders[].id'); do
    folder_status=$(curl -s -H "X-API-Key: $API_KEY" "$API_URL/db/status?folder=$folder_id" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$folder_status" ]; then
      state=$(echo "$folder_status" | jq -r '.state')
      if [[ "$state" == "error" ]]; then
        sync_errors=$((sync_errors + 1))
      fi
    fi
  done
fi

# Determine status icon and class
if [ "$sync_errors" -gt 0 ]; then
  icon="󰚌" # Sync error
  class="error"
  tooltip="Syncthing: $sync_errors sync errors in $folder_count folders"
elif [ "$syncing" -gt 0 ]; then
  icon="󰎔" # Syncing
  class="syncing"
  tooltip="Syncthing: Syncing data ($folder_count folders)"
else
  icon="󰁪" # Idle/synced
  class="idle"
  tooltip="Syncthing: Up to date ($folder_count folders)"
fi

# Format uptime for tooltip
if [ "$uptime" -gt 0 ]; then
  hours=$((uptime / 3600))
  minutes=$(((uptime % 3600) / 60))
  if [ "$hours" -gt 0 ]; then
    uptime_str="${hours}h ${minutes}m"
  else
    uptime_str="${minutes}m"
  fi
  tooltip="$tooltip • Uptime: $uptime_str"
fi

# Output JSON for Waybar
echo "{\"text\": \"$icon\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
