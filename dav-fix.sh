#!/bin/bash

set -e  # Exit on any error

sudo su
apt update
apt install inotify-tools ffmpeg

systemctl stop davConvert.service
systemctl disable davConvert.service

rm /etc/systemd/system/davConvert.service
systemctl daemon-reload && sudo systemctl reset-failed

rm /tmp/davConvert.lock
rm /usr/local/bin/davConvert.sh

echo "✅ davConvert removed"

CRON_JOB="1 * * * * sudo systemctl restart davConvert.service"

# Dump crontab to a temp file
crontab -l > mycron.tmp 2>/dev/null

# Remove the matching cron line
grep -vF -x "$CRON_JOB" mycron.tmp > mycron.new

# Install the new crontab
crontab mycron.new

# Clean up
rm -f mycron.tmp mycron.new

echo "If the cron job existed, it has now been removed."


# Placeholder for the content of davConvert.sh
read -r -d '' DAVCONVERT_SH_CONTENT << 'EOF'
#!/bin/bash

MISSED_QUEUE="/tmp/missed_dav_queue.txt"
touch "$MISSED_QUEUE"

LOCKFILE="/tmp/davConvert.lock"
exec 9>"$LOCKFILE"
flock -n 9 || {
    log_message "Another instance is running. Exiting."
    exit 1
}

# Configuration: Paths and dependencies
BASE_DIRS=("/home/user/DHRecs/Camera2" "/home/user/DHRecs/Camera1")  # Multiple directories to monitor
FFMPEG_PATH="/usr/bin/ffmpeg"
LOG_FILE="/var/log/davConvert.log"

MAX_CONCURRENT_MONITORS=50
CURRENT_MONITORS=0

# Ensure required dependencies are installed
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotify-tools is not installed." | tee -a "$LOG_FILE"
    exit 1
fi

if ! command -v "$FFMPEG_PATH" &> /dev/null; then
    echo "Error: ffmpeg is not installed." | tee -a "$LOG_FILE"
    exit 1
fi

# Function to log messages with timestamp
log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to convert .dav to .mp4
#convert_dav_to_mp4() {
#    local dav_file="$1"
#    local mp4_file="${dav_file%.dav}.mp4"
#    local lock_file="$dav_file.lock"

    # Use flock to prevent concurrent access to the file
#    (
#        flock -n 200 || exit 1  # If another process holds the lock, exit immediately
#        log_message "Converting $dav_file to $mp4_file..."

#        "$FFMPEG_PATH" -i "$dav_file" -c:v libx264 -c:a aac -strict experimental "$mp4_file"

#	if [ $? -eq 0 ]; then
#    		log_message "Conversion successful: $dav_file -> $mp4_file"
#    		rm -f "$dav_file"
#	else
#    		log_message "Conversion failed: $dav_file"
#	fi

#    ) 200>"$lock_file"  # This file is used to lock access to the file

#    # Remove the lock file once done
#    rm -f "$lock_file"
#}
#convert_dav_to_mp4() {
#    local dav_file="$1"
#    local mp4_file="${dav_file%.dav}.mp4"
#    local lock_file="$dav_file.lock"

#    (
#        flock -n 200 || exit 1
#        log_message "Converting $dav_file to $mp4_file (stream copy)..."

#        "$FFMPEG_PATH" -i "$dav_file" -c copy -movflags +faststart "$mp4_file"
#        if [ $? -ne 0 ]; then
#            log_message "Stream copy failed. Re-encoding $dav_file to H.265"
#            "$FFMPEG_PATH" -i "$dav_file" -c:v libx265 -preset ultrafast -c:a copy "$mp4_file"
#        fi

#        if [ $? -eq 0 ]; then
#            log_message "Conversion successful: $dav_file -> $mp4_file"
#            rm -f "$dav_file"
#        else
#            log_message "Conversion failed: $dav_file"
#        fi
#    ) 200>"$lock_file"

#    rm -f "$lock_file"
#}
convert_dav_to_mp4() {
    local dav_file="$1"
    local mp4_file="${dav_file%.dav}.mp4"
    local lock_file="$dav_file.lock"

    (
        flock -n 200 || exit 1
        log_message "Converting $dav_file to $mp4_file (H.265 ? H.264 re-encode)..."

        "$FFMPEG_PATH" -y -i "$dav_file" \
            -c:v libx264 -preset ultrafast -crf 23 \
            -c:a aac -b:a 128k \
            -movflags +faststart \
            "$mp4_file"

        if [ $? -eq 0 ]; then
            log_message "Conversion successful: $dav_file -> $mp4_file"
            rm -f "$dav_file"
        else
            log_message "Conversion failed: $dav_file"
        fi
    ) 200>"$lock_file"

    rm -f "$lock_file"
}


# Function to kill existing inotifywait processes
kill_existing_inotify() {
    log_message "Killing existing inotifywait processes..."
    pkill -f "inotifywait"
}

# Function to wait for the file to be stable before converting
#wait_for_file_stability() {
#    local file="$1"
#    local max_retries=5
#    local retry_interval=2  # in seconds

#    for i in $(seq 1 $max_retries); do
#        # Check if the file size is changing
#        initial_size=$(stat --format=%s "$file")
#        sleep $retry_interval
#        current_size=$(stat --format=%s "$file")

#        if [ "$initial_size" -eq "$current_size" ]; then
#            return 0  # File is stable, proceed with conversion
#        fi
#    done

#    return 1  # File is not stable after several retries
#}
wait_for_file_stability() {
    local file="$1"
    local max_retries=5
    local retry_interval=2  # in seconds

    for i in $(seq 1 $max_retries); do
        initial_size=$(stat --format=%s "$file" 2>/dev/null) || return 1
        sleep $retry_interval
        current_size=$(stat --format=%s "$file" 2>/dev/null) || return 1

        if [ "$initial_size" -eq "$current_size" ]; then
            return 0  # File is stable
        fi
    done

    log_message "File not stable after retries: $file � queuing for later"
    echo "$file" >> "$MISSED_QUEUE"
    return 1
}


# Function to monitor the current date and hour directory for a given BASE_DIR
monitor_current_hour_directory() {
    local base_dir="$1"
    local current_day=$(date +'%Y-%m-%d')
    local current_hour=$(date +'%H')
    local hour_dir="$base_dir/$current_day/001/dav/$current_hour"

    log_message "Monitoring directory $hour_dir for new files..."

    # If the directory does not exist, wait for it to appear
    while [ ! -d "$hour_dir" ]; do
        log_message "Directory $hour_dir does not exist. Waiting..."
        sleep 10  # Wait before checking again
    done

    # Once the directory is present, monitor for new .dav files
    inotifywait -m -r -e create,moved_to --format '%w%f' "$hour_dir" | while read new_file
    do
        # Wait a little before starting conversion to catch any other files in quick succession
        sleep 1  # Adjust the sleep duration based on the expected rate of file creation

        # Handle .dav_ temporary files
        if [[ "$new_file" =~ \.dav_$ ]]; then
            echo "Detected temporary .dav file: $new_file"
        fi

	if [[ "$new_file" =~ \.dav$ ]]; then
	    echo "Detected .dav file: $new_file"
	    if wait_for_file_stability "$new_file"; then
	        convert_dav_to_mp4 "$new_file" &
	    fi
	fi


        # Handle finalized .dav files
#        if [[ "$new_file" =~ \.dav$ ]]; then
#            echo "Detected .dav file: $new_file"
#            convert_dav_to_mp4 "$new_file" &  # Run in background to handle multiple files concurrently
#        fi
    done
}

# Function to check and process any missed .dav files every 2 minutes for a given BASE_DIR
#recheck_missed_files() {
#    local base_dir="$1"
#    local current_day=$(date +'%Y-%m-%d')
#    local day_dir="$base_dir/$current_day"  # Directory for the current day

#    while true; do
#        # Get the current hour in a 2-digit format (e.g., 09, 10, etc.)
#        current_hour=$(date +'%H')

#        # Loop through hours from the current hour down to 00
#        for hour in $(seq -f "%02g" "$current_hour" -1 0); do
#            local hour_dir="$day_dir/001/dav/$hour"

#            # Check if the hour directory exists and contains .dav files
#            if [ -d "$hour_dir" ] && find "$hour_dir" -type f -name "*.dav" | grep -q .; then
#                log_message "Checking directory $hour_dir for missed .dav files"

#                # Find and process any .dav files in this directory
#                find "$hour_dir" -type f -name "*.dav" | while read missed_file; do
#                    log_message "Rechecking missed .dav file: $missed_file"
#                    convert_dav_to_mp4 "$missed_file"
#                done
#                break  # Once a directory with .dav files is found, stop going back further
#            fi
#        done

#        # Wait 2 minutes before scanning again
#        sleep 120
#    done
#}
recheck_missed_files() {
    local base_dir="$1"

    while true; do
        # Process current and previous day
        for offset in 0 1; do
            local target_day=$(date -d "-$offset day" +'%Y-%m-%d')
            local day_dir="$base_dir/$target_day"

            current_hour=$(date +'%H')
            # If checking today, go backward from current hour
            # If checking yesterday, go backward from 23
            local max_hour=$(( offset == 0 ? 10#$current_hour : 23 ))

            for hour in $(seq -f "%02g" "$max_hour" -1 0); do
                local hour_dir="$day_dir/001/dav/$hour"

                if [ -d "$hour_dir" ] && find "$hour_dir" -type f -name "*.dav" | grep -q .; then
                    log_message "Checking directory $hour_dir for missed .dav files (day: $target_day)"

                    find "$hour_dir" -type f -name "*.dav" | while read missed_file; do
                        log_message "Rechecking missed .dav file: $missed_file"
                        convert_dav_to_mp4 "$missed_file"
                    done

                    # Once we found and processed files, we can skip the rest of the hours for that day
                    break
                fi
            done
        done

        # Wait 2 minutes before the next scan
        sleep 120
    done
}

process_missed_files() {
    while true; do
        if [ -s "$MISSED_QUEUE" ]; then
            log_message "Processing missed file queue..."

            # Create a temp file to avoid conflicts during append
            cp "$MISSED_QUEUE" "$MISSED_QUEUE.tmp"
            > "$MISSED_QUEUE"  # Clear original queue before retrying

            while read missed_file; do
                if [ -f "$missed_file" ]; then
                    if wait_for_file_stability "$missed_file"; then
                        log_message "Retrying missed file: $missed_file"
                        convert_dav_to_mp4 "$missed_file"
                    else
                        log_message "Still unstable, re-queueing: $missed_file"
                        echo "$missed_file" >> "$MISSED_QUEUE"
                    fi
                else
                    log_message "Missed file no longer exists: $missed_file"
                fi
            done < "$MISSED_QUEUE.tmp"

            rm -f "$MISSED_QUEUE.tmp"
        fi

        sleep 60  # Check every 60 seconds
    done
}


# Gracefully handle shutdown
trap 'log_message "Shutting down..."; exit 0' SIGINT SIGTERM

# Kill any running inotifywait processes before restarting
kill_existing_inotify

# Start monitoring each BASE_DIR directory
for base_dir in "${BASE_DIRS[@]}"; do
    monitor_current_hour_directory "$base_dir" &
    recheck_missed_files "$base_dir" &
done

# Self-restart mechanism: watch for hour or day change
last_hour=$(date +'%H')
last_day=$(date +'%Y-%m-%d')

(
    while true; do
        current_hour=$(date +'%H')
        current_day=$(date +'%Y-%m-%d')
        if [ "$current_hour" != "$last_hour" ] || [ "$current_day" != "$last_day" ]; then
            log_message "Date/hour changed from $last_day $last_hour to $current_day $current_hour. Restarting script..."
            exec "$0" "$@"  # Replace current process with a fresh instance
        fi
        sleep 60
    done
) &

process_missed_files &

wait  # Wait for all background processes

EOF

# Placeholder for the content of davConvert.service
read -r -d '' DAVCONVERT_SERVICE_CONTENT << 'EOF'
[Unit]
Description=Monitor Dahua Video Files and Convert .dav to .mp4
After=network.target

[Service]
ExecStart=/usr/local/bin/davConvert.sh
Restart=on-failure
RestartSec=10s
User=user
Group=user
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=/home/user

[Install]
WantedBy=multi-user.target

EOF

# Create davConvert.sh script
echo "$DAVCONVERT_SH_CONTENT" > /tmp/davConvert.sh
chmod +x /tmp/davConvert.sh
sudo mv /tmp/davConvert.sh /usr/local/bin/davConvert.sh

# Create davConvert.service
echo "$DAVCONVERT_SERVICE_CONTENT" | sudo tee /etc/systemd/system/davConvert.service > /dev/null

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable and start the service
sudo systemctl enable davConvert.service
sudo systemctl start davConvert.service

# Show the service status
# sudo systemctl status davConvert.service

# Add the cron job to restart the service every hour
#(crontab -l 2>/dev/null; echo "1 * * * * sudo systemctl restart davConvert.service") | crontab -

# Modify sudoers file to allow the user to restart the service without a password
sudo visudo -c
echo "user ALL=(ALL) NOPASSWD: /bin/systemctl restart davConvert.service" | sudo tee -a /etc/sudoers > /dev/null

echo "Setup complete!"
