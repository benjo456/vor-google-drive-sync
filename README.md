# Vor Sync Script

## Description

This script is designed to continuously sync video recordings (`.mov` files) from a local directory to Google Drive. It's particularly useful for situations where you need to upload large video files as they're being recorded, ensuring that the upload is nearly complete by the time the recording finishes.

## Features

- Continuous syncing of `.mov` files as they're being recorded
- Efficient handling of large files
- Cleanup of temporary files
- Graceful interrupt handling
- Detailed logging of activities

## Requirements

- Bash shell
- rsync
- rclone (configured for Google Drive)


## Usage

1. Navigate to the script directory:
cd vor-sync-script
2. Make the script executable:
chmod +x sync_recordings.sh
3. Run the script:
./sync_recordings.sh

The script will start syncing files from the specified local directory to Google Drive. It will continue running until interrupted with Ctrl+C.

## Configuration

Edit the following variables at the top of `sync_recordings.sh` to match your setup:

- `LOCAL_RECORDINGS`: Path to the directory containing the video recordings
- `TEMP_COPY_BASE`: Path to a temporary directory for intermediate copies
- `REMOTE_PATH`: rclone path for the Google Drive destination
- `SYNC_INTERVAL`: Time in seconds between sync cycles
- `STABLE_TIME`: Time in seconds between stability checks
- `STABLE_CHECK_COUNT`: Number of times to check for stability

## Logging

The script logs its activities to a file specified by `LOGFILE`. You can monitor this file to track the script's progress and diagnose any issues.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[MIT License](LICENSE)