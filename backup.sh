#!/bin/bash

# Exit early on any error
set -euo pipefail

# Function to print usage
usage() {
    cat <<EOF
Usage:
    backup -s <source> -H <home> -l <label> -u <username> -h <hostname> -d <destination>

Options:
    -s <source>             The path to the file to backup
    -H <home>               The home directory of the file system to keep scope in cron job
    -l <label>              The label of the backup file. The backup file name is the label + timestamp.
    -u <username>           The username of the remote to send the backup file to
    -h <hostname>           The hostname of the remote to send the backup file to
    -d <destination>        The directory where the backup file is placed on the remote
EOF
    exit 1
}

# Initialize option values
source=""
home=""
label=""
remote_user=""
remote_hostname=""
remote_destination=""

# Check we have all arguments
if [[ $# -lt 6 ]]; then
    usage
fi

# Extract options
while getopts "s:H:l:u:h:d:" opt; do
    case $opt in
        s)
            source="$(readlink -f "$OPTARG")" ;;
        H)
            home="$(readlink -f "$OPTARG")" ;;
        l)
            label="$OPTARG" ;;
        u)
            remote_user="$OPTARG" ;;
        h)
            remote_hostname="$OPTARG" ;;
        d)
            remote_destination="${OPTARG#/}" ;;
        *)
            usage ;;
    esac
done

# Shift past parsed options
shift $((OPTIND-1))

# Install a cron job for this script
register_cron() {
    # At 12pm every Saturday
    schedule="0 12 * * 6"
    # Get absolute script path for cron
    script="$(readlink -f "$0")"
    # Explicit arguments to get absolute source and home path for cron
    args="-s $source -H $home -l $label -u $remote_user -h $remote_hostname -d \"/${remote_destination}\""
    logfile="$home/Backups/backup.log"

    # Make sure local backup directory exists
    if [[ ! -d "$(dirname "$logfile")" ]]; then
        mkdir -p "$(dirname "$logfile")"
    fi

    # This script with all arguments originally passed in
    command="$schedule $script $args >> $(printf '%q' $logfile) 2>&1"

    # Check if cron job is already registered for this script
    if ! crontab -l 2>/dev/null | grep -Fxq "$command" > /dev/null; then
        (crontab -l 2>/dev/null; echo "$command") |  crontab -
        echo "Installed cron job $command"
    fi
}

# Backup a folder and sync it to a remote host
run_backup() {
    date=$(date +%F-%H%M)
    tarball="$home/Backups/$label-$date.tar.gz"

    # Create a tarball in local backup directory
    tar -czf "$tarball" "$source"

    # Send tarball to another machine
    rsync -avz -e "ssh -i $home/.ssh/id_ed25519 -o BatchMode=yes" "$tarball" "$remote_user@$remote_hostname:~/${remote_destination}/$(basename "$tarball")"

    if [ $? -eq 0 ]; then
        echo "Rsync successful"
    else
        echo "Rsync failed"
    fi
}

register_cron
run_backup