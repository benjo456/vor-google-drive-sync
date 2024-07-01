#!/bin/bash

LOCAL_RECORDINGS="$HOME/Documents/Vor"
TEMP_COPY_BASE="$HOME/Documents/Vor/temp"
REMOTE_PATH="drive:/vorsync"
SYNC_INTERVAL=2  # Time in seconds between syncs
STABLE_TIME=2  # Time in seconds between stability checks
STABLE_CHECK_COUNT=3  # Number of times to check for stability
LOGFILE="$HOME/Documents/Vor/sync.log"
PROCESSED_FILES="$HOME/Documents/Vor/processed_files.txt"

# Create the temp directory if it doesn't exist
mkdir -p "$TEMP_COPY_BASE"

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

# Function to get the maximum processed size for a file
get_max_processed_size() {
    local filename="$1"
    awk -F, -v fn="$filename" '$1 == fn {if ($2 > max) max = $2} END {print max}' "$PROCESSED_FILES"
}

cleanup() {
    log "Interrupt received, performing final sync..."
    for file in "$LOCAL_RECORDINGS"/*.mov; do
        if [ -f "$file" ]; then
            base_filename=$(basename "$file")
            current_size=$(stat -f %z "$file" | tr -d '\n')
            
            # Get the maximum processed size for this file
            processed_size=$(get_max_processed_size "$base_filename")

            # Ensure processed_size is a number
            if [ -z "$processed_size" ]; then
                processed_size=0
            fi

            if [ "$current_size" -le "$processed_size" ]; then
                log "Skipping already processed file: $file"
                continue
            fi
            
            # Check if file is still being written
            initial_size=$current_size
            sleep 5  # Wait for 5 seconds
            current_size=$(stat -f %z "$file" | tr -d '\n')
            
            if [ "$initial_size" -ne "$current_size" ]; then
                log "File $file is still being written. Waiting for it to stabilize..."
                
                # Wait for file to stabilize
                stable=false
                for i in {1..12}; do  # Try for up to 1 minute (12 * 5 seconds)
                    initial_size=$current_size
                    sleep 5
                    current_size=$(stat -f %z "$file" | tr -d '\n')
                    if [ "$initial_size" -eq "$current_size" ]; then
                        stable=true
                        break
                    fi
                done
                
                if ! $stable; then
                    log "File $file did not stabilize. Skipping final sync for this file."
                    continue
                fi
            fi
            
            log "Performing final sync for: $file"
            rclone copy --update --verbose "$file" "$REMOTE_PATH" 2>&1 | tee -a "$LOGFILE"
            
            if [ $? -eq 0 ]; then
                log "Final sync successful for: $file"
                # Update the processed file list with the new size
                awk -F, -v fn="$base_filename" -v sz="$current_size" '
                    $1 != fn {print}
                    END {print fn "," sz}
                ' "$PROCESSED_FILES" > "$PROCESSED_FILES.tmp"
                mv "$PROCESSED_FILES.tmp" "$PROCESSED_FILES"
            else
                log "Final sync failed for: $file"
            fi
        fi
    done
    log "Final sync complete. Exiting."
    exit 0
}

trap cleanup SIGINT SIGTERM

log "Starting sync script."

touch "$PROCESSED_FILES"

process_file() {
    local file="$1"
    base_filename=$(basename "$file")
    temp_copy="$TEMP_COPY_BASE/$base_filename"

    # Get the current file size
    current_size=$(stat -f %z "$file" | tr -d '\n')

    # Get the maximum processed size for this file
    processed_size=$(get_max_processed_size "$base_filename")

    # Ensure processed_size is a number
    if [ -z "$processed_size" ]; then
        processed_size=0
    fi

    if [ "$current_size" -le "$processed_size" ]; then
        return
    fi

    log "Syncing file: $file"
    # Use rsync to copy the file incrementally to the temp directory
    rsync -av --inplace "$file" "$TEMP_COPY_BASE/" 2>&1 | tee -a "$LOGFILE"

    log "Copying to Google Drive."
    # Copy to Google Drive
    rclone copy --update "$temp_copy" "$REMOTE_PATH" 2>&1 | tee -a "$LOGFILE"

    # Check if file has become stable
    stable_checks=0
    while [ $stable_checks -lt $STABLE_CHECK_COUNT ]; do
        sleep "$STABLE_TIME"
        new_size=$(stat -f %z "$file" | tr -d '\n')
        if [ "$current_size" -eq "$new_size" ]; then
            ((stable_checks++))
        else
            stable_checks=0
            current_size=$new_size
            break
        fi
    done

    if [ $stable_checks -eq $STABLE_CHECK_COUNT ]; then
        log "File deemed stable: $file"
        # File is stable, ensure it is fully uploaded
        log "Performing final upload for stable file: $file"
        rclone copy --update "$file" "$REMOTE_PATH" 2>&1 | tee -a "$LOGFILE"

        # Update the processed file list with the new size
        awk -F, -v fn="$base_filename" -v sz="$current_size" '
            $1 != fn {print}
            END {print fn "," sz}
        ' "$PROCESSED_FILES" > "$PROCESSED_FILES.tmp"
        mv "$PROCESSED_FILES.tmp" "$PROCESSED_FILES"

        # After ensuring the file is fully uploaded, clean up temp file
        log "Cleaning up temp file: $temp_copy"
        rm -f "$temp_copy"
    else
        log "File still changing: $file"
    fi
}

last_processed_time=0

while true; do
    current_time=$(date +%s)
    files_processed=0

    for file in "$LOCAL_RECORDINGS"/*.mov; do
        if [ -f "$file" ]; then
            file_mod_time=$(stat -f %m "$file")
            if [ $file_mod_time -gt $last_processed_time ]; then
                process_file "$file"
                files_processed=$((files_processed + 1))
            fi
        fi
    done

    if [ $files_processed -eq 0 ]; then
        log "No changes detected. Waiting..."
    fi

    last_processed_time=$current_time
    sleep "$SYNC_INTERVAL"
done