#!/bin/bash

if [ "$EUID" -ne 0 ]; then     # Check if the effective user ID is not 0 (zero is the root user)
    echo "Please run as root." # The script needs to be run as root
    exit 1                     # Exit the script with an error code
fi

if ! command -v ping >/dev/null 2>&1; then                       # Check if the ping command is not available and redirect output to /dev/null and error to standard output (so also redirected to /dev/null)
    echo "The ping command is not available. Please install it." # If the ping command is not available
    exit 1                                                       # Exit the script with an error code
fi

if ! ping -c 1 google.com >/dev/null 2>&1; then                            # Check if the ping command is successful and send output to /dev/null
    echo "Internet connection is down, some features will be unavailable." # If the ping command is not successful then the internet connection is down
fi

# Package maintenance function
audit_packages() {
    echo "Checking for software updates..."

    # Detect the Linux distribution
    if command -v apt-get &>/dev/null; then # Check if apt-get is available and send output to /dev/null
        # Update the package list
        apt-get update

        # Upgrade all packages
        apt-get upgrade -y

        # Remove unnecessary packages
        apt-get autoremove -y

        # Clean up the package cache
        apt-get clean

        # Check for broken dependencies
        apt-get check

        # Upgrade the distribution
        do-release-upgrade
    elif command -v pacman &>/dev/null; then # Check if pacman is available and send output to /dev/null

        # Pacman uses less commands to accomplish the same tasks, so arch is better
        # Update the package list and upgrade all packages
        pacman -Syu

        # Remove all orphaned packages
        pacman -Rns "$(pacman -Qdtq)"

        # Clean up the package cache
        pacman -Scc
    else
        echo "Unable to detect OS."
        exit 1 # Exit the script with an error code
    fi
    # Check if AIDE is installed and send output to /dev/null
    if command -v aide &>/dev/null; then
        read -r -p "Do you want to create a new snapshot for AIDE? (yes/no): " snapshot # Ask if the user wants to create a new snapshot
        if [ "$snapshot" = "yes" ]; then # Check if user entered yes
            echo "Updating AIDE database to create a new snapshot..."
            aide --update # Update the AIDE database
        else
            echo "AIDE is not installed. Cannot create a new snapshot. Run File Integrity Check first to install AIDE."
        fi
    fi    
}

# File integrity check function
check_file_integrity() {
    # Code for file integrity check goes here
    echo "Checking file integrity..."

    # Define the spinner characters
    spinner=('|' '/' '-' "\\")
    i=0 # Counter for spinner
    # Check package manager for ubuntu based distros
    if command -v apt-get &>/dev/null; then
        # Check if AIDE is installed
        if ! command -v aide &>/dev/null; then
            echo "AIDE could not be found. Installing..."
            apt-get install aide
        fi

        # Initialize the database if it doesn't exist
        if [ ! -f /var/lib/aide/aide.db.gz ]; then
            (sleep 3 && while true; do                           # Sleep for 3 seconds and start the spinner
                printf "\b%s" "${spinner[i++ % ${#spinner[@]}]}" # Print the spinner character (using prinf instead of echo -ne and so also %s as this was recommended in the shellcheck warning SC2059)
                sleep 0.1                                        # sleep for 0.1 seconds
            done) &                                              # Run in the background
            spinner_pid=$!                                       # Save the spinner PID
            if command -v aideinit &>/dev/null; then
                aideinit >aideinit_report.txt 2>/dev/null &              # Initialize the AIDE database and redirect errors
                mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz # Change the name of the new database so aide can recognize it
                aideinit_pid=$!                                          # Save the AIDE init PID
                wait $aideinit_pid                                       # Wait for AIDE init to finish
            fi
            kill $spinner_pid # Kill the spinner
        fi

        # Check file integrity
        (sleep 3 && while true; do
            printf "\b%s" "${spinner[i++ % ${#spinner[@]}]}"
            sleep 0.1
        done) &
        spinner_pid=$!
        aide --check >aidecheck_report.txt 2>/dev/null & # Check file integrity and redirect errors run in the background
        aide_check_pid=$!                                # Save the AIDE check PID
        wait $aide_check_pid                             # Wait for AIDE check to finish
        kill $spinner_pid
    # Check package manager for arch based distros
    elif command -v pacman &>/dev/null; then
        # Check if AIDE is installed
        if ! command -v aide &>/dev/null; then
            echo "AIDE could not be found. Installing..."
            yay -S aide-selinux # Install AIDE with yay
        fi

        # Initialize the database if it doesn't exist
        if [ ! -f /var/lib/aide/aide.db.gz ]; then
            (sleep 3 && while true; do                           # Sleep for 3 seconds and start the spinner
                printf "\b%s" "${spinner[i++ % ${#spinner[@]}]}" # Print the spinner character
                sleep 0.1                                        # sleep for 0.1 seconds
            done) &                                              # Run in the background
            spinner_pid=$!                                       # Save the spinner PID
            if command -v aideinit &>/dev/null; then
                aideinit >aideinit_report.txt 2>/dev/null & # Initialize the AIDE database and redirect errors
                aideinit_pid=$!                             # Save the AIDE init PID
                wait $aideinit_pid                          # Wait for AIDE init to finish
            fi
            kill $spinner_pid # Kill the spinner
        fi

        # Check file integrity
        (sleep 3 && while true; do
            printf "\b%s" "${spinner[i++ % ${#spinner[@]}]}"
            sleep 0.1
        done) &
        spinner_pid=$!
        aide --check >aidecheck_report.txt 2>/dev/null & # Check file integrity and redirect errors run in the background
        aide_check_pid=$!                                # Save the AIDE check PID
        wait $aide_check_pid                             # Wait for AIDE check to finish
        kill $spinner_pid
    else
        echo "Unsupported OS."
        exit 1
    fi
    echo "File integrity check complete and report saved to current directory. Press any key to return to main menu..."
    read -r -n 1 -p ""
}

# Permissions audit function
audit_permissions() {
    echo "Choose a directory to audit:"
    # Enter one or more directories to audit
    read -rp "Enter directory paths (separated by space): " -a dirs
    # Create a report file to save the results
    perm_report="permissions_report.txt"
    # Define weak permissions to check for
    weak_permissions=("o+rw" "g+rw" "777")
    # Append to the report file
    echo "Audit conducted on $(date)" >$perm_report
    for dir in "${dirs[@]}"; do # Iterate through all directories entered by the user
        echo "Report for directory: $dir" >>"$perm_report"
        if [ ! -d "$dir" ]; then                           # If the directory does not exist then
            echo "Error: Directory '$dir' does not exist." # Print an error message
            exit 1                                         # Exit the script with an error code
        fi
        echo -n "Checking permissions in $dir  "
        # Check for weak permissions in the directories
        echo "Weak permissions found:" >>$perm_report
        for perm in "${weak_permissions[@]}"; do # Interate through all weak permissions in the list
            # Start the spinner
            spinner=('|' '/' '-' "\\")                           # Define the spinner characters
            i=0                                                  # Counter for spinner
            (sleep 3 && while true; do                           # Start the spinner after 3 seconds
                printf "\b%s" "${spinner[i++ % ${#spinner[@]}]}" # Backspace the previous character and calculate the index of the next spinner character and print
                sleep 0.1                                        # Sleep for 0.1 seconds
            done) &                                              # Run in the background
            spinner_pid=$!                                       # Save the spinner PID
            # Find and redirect errors
            find "$dir" -type f -perm "$perm" -exec ls -l {} \; >>"$perm_report" 2>/dev/null & # Find files with weak permissions and append to the report ignoring errors and run in the background
            find_pid=$!                                                                        # Save the find PID
            # Wait for find to finish
            wait $find_pid
            # Stop the spinner once find finishes
            kill $spinner_pid
        done
        echo "Checking for SUID files..."
        echo "Files with SUID permissions:" >>"$perm_report"
        find "$dir" -user root -perm -4000 -type f 2>/dev/null >>"$perm_report" # Find files with SUID bit set and owned by root and append to the report
    done
    cat $perm_report # Display the report
    # Tell the user the report is saved
    echo ""                             # Print a new line
    echo "Report saved to $perm_report" # Print the location of the report
    echo "Scan complete. Press any key to go back to main menu..."
    read -r -n 1 -p ""
}

# User accounts and sudoers audit
audit_users() {
    # Define variables
    passwd_file="/etc/passwd"
    shadow_file="/etc/shadow"
    secure_copy="/var/log/secure_passwd_copy"
    user_report="user_report.txt"

    echo ""
    echo "Auditing user accounts and sudoers file..."

    # Check for users without passwords
    echo "Checking for users without passwords..."
    echo ""
    echo "Audit conducted on $(date)" >$user_report # Append to the date to the report
    echo "Users without passwords:" >"$user_report" # Append to the report
    # Find users without passwords and append to the report
    awk -F: '($2 == "") {print $1}' "$shadow_file" >>"$user_report" # Set the field separator to : and print the first field if the second field is empty
    if [ ! -f "$secure_copy" ]; then                                # Check if the secure copy file does not exist
        echo "Creating initial baseline copy of passwd file..."
        cp "$passwd_file" "$secure_copy" # Copy the passwd file to the secure copy file
        chmod 600 "$secure_copy"         # Change the permissions of the secure copy file
    fi

    # Compare password files and identify new users
    echo "New users since last check:" >>"$user_report" #
    # Compare the sorted secure copy and the passwd file and append to the report
    comm -13 <(sort "$secure_copy") <(sort "$passwd_file") >>"$user_report" # Supress lines that are unique to the first file and lines that are common to both files
    if [ -s "$user_report" ]; then                                          # Check if report is not empty
        echo "Security issues detected! Report:"
        # Display the report
        cat "$user_report"
    else
        echo "No new issues detected since last check."
    fi

    # Update the secure copy
    cp "$passwd_file" "$secure_copy"
    echo "Scan complete $user_report created. Press any key to go back to main menu..."
    read -r -n 1 -p ""
}

initiate_firwall() {
    # Check if the firewall is installed
    if command -v ufw &>/dev/null; then
        echo "UFW is installed."
        # Reset the firewall, gives option
        ufw reset
    else # If the firewall is not installed
        echo "UFW is not installed. Installing..."
        # Check the package manager and install ufw
        if command -v apt-get &>/dev/null; then
            apt-get install ufw
        elif command -v pacman &>/dev/null; then
            pacman -S ufw
        else
            echo "Unsupported OS."
            exit 1
        fi
    fi

    # Enable the firewall
    ufw enable

    # Set the default policy to deny incoming
    ufw default deny incoming

    # Set the default policy to allow outgoing
    ufw default allow outgoing

    # Ask user for ports to open
    while true; do
        echo "Enter the ports you want to open, separated by space or none to cancel:"
        read -r ports

        # Check if the user has changed their mind
        if [ "$ports" = "none" ]; then # Check if the user has entered 'none'
            echo "Port input cancelled."
            break # If 'none' then break the loop
        fi

        # Validate the ports
        valid=true # Set the valid flag to true
        for port in $ports; do
            # Check if the ports are one or more numbers from 0-9 starting from ^ and ending with $
            if ! [[ $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then # Also Check if the port is less than 1 or greater than 65535
                echo "Invalid port: $port"
                valid=false # Set the valid flag to false
                break       # Break the loop
            fi
        done
        if $valid; then # If the valid flag is true
            break       # Break the loop
        else
            echo "Please enter valid ports or type 'none' to cancel."
        fi
    done

    # Ask user if they want to rate limit the ports
    echo "Do you want to rate limit the ports? (yes/no)"
    read -r rate_limit

    # Open the ports
    for port in $ports; do
        if [ "$rate_limit" = "yes" ]; then # Check if the user wants to rate limit the ports
            ufw limit "$port"              # Rate limit the port
        else
            ufw allow "$port" # Open without limit
        fi
    done

    # Ask user for logging level
    echo "Choose logging level (off, low, medium, high, full):"
    read -r log_level

    # Set logging level
    ufw logging "$log_level"

    # Display the status of the firewall
    ufw status verbose

    # Reload the firewall
    ufw reload

    echo "Firewall initiated. Press any key to go back to main menu..."
    read -r -n 1 -p ""
}

# Main menu
while true; do # Run an infinite loop for menu
    echo "System Security Auditor"
    # Dragon image
    dragon_image="
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣴⣶⡿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣴⣾⣿⣿⡿⠟⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡴⢚⢫⣽⣿⣿⡿⠛⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⡶⠛⠳⣎⢥⣿⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⡿⠁⠀⠀⠀⣹⢾⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⣆⣆⣶⣶⣶⡶⣶⢶⣀⣀⣀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⡴⢛⡏⠀⠀⠀⣠⡖⢏⠺⣿⣿⣷⣦⣤⣤⣤⠶⠖⠊⠀⠀⣀⣤⣤⡴⣖⡾⠟⠛⠉⠉⠉⠙⣏⡞⣼⣼⣷⣿⡿⠿⠛⠉⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⣠⠾⣉⠖⡩⢝⡦⠴⣞⠱⡸⢌⣣⣽⣿⣿⠿⠛⠉⣀⣠⣤⣶⡾⠟⠛⠋⠉⠙⣾⣇⠀⠀⠀⢀⣀⣤⣿⣿⣿⠿⠛⠉⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⢀⣴⢋⠖⡱⢊⡕⢪⢔⠫⡔⢫⣱⣾⠿⠛⢉⣠⡴⣶⠿⠟⠋⠁⠀⠀⠀⠀⠀⢀⣠⡿⣹⢳⣻⠻⡽⣹⣿⣿⡟⠁⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⣰⠟⣤⢋⡎⢵⡩⢜⢣⢎⣣⣽⠟⢋⣡⡴⣞⣯⠟⠋⠁⠀⠀⠀⠀⣀⣤⢶⢶⣛⢯⣓⢧⣓⡏⣶⢫⣽⣿⣿⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠼⢯⣞⡤⢳⡸⢅⡞⣩⣖⠷⠋⠳⢶⣏⢧⣽⠋⠀⠀⠀⢀⣠⡴⣞⡻⡝⣮⢝⡲⣭⢞⡼⣣⢧⣛⢶⣫⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠈⠻⣵⢊⠷⡸⢥⣧⠀⠀⠀⠀⠉⠳⣾⣦⣠⣤⡞⣯⠳⣝⡲⣭⢳⣣⢏⡷⢳⣎⢷⡹⢮⡝⣮⢳⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⣸⣏⣞⣱⡧⠾⢷⣄⡀⠀⠀⠀⠈⠳⣏⡶⣹⢖⡻⣜⡳⣭⢳⡭⣞⡽⣳⢎⡷⣹⢧⣻⠼⣏⢿⣿⣿⣿⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⣤⣿⣩⣥⣶⣿⣭⣶⣿⠿⠛⠛⠀⠀⠙⣷⡹⣎⠷⣭⢳⣭⢳⡝⣮⢳⣝⢾⡹⢧⣟⢮⣟⣭⢿⣮⣝⠻⢿⣧⡀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⣠⡴⣞⡟⣻⣛⢿⡻⣿⣿⣦⣤⣄⡀⠀⠀⠀⢹⡷⣭⣻⢼⡳⣞⡽⣺⡭⣟⢮⣯⢽⣻⡼⣏⡾⣞⡽⣞⡿⣿⣦⣈⠉⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⣰⠿⣭⣷⣭⡞⣵⡹⣎⠷⣭⣛⣿⣿⣭⣉⠀⠀⠀⠀⢿⣧⣛⣮⢷⣫⣞⠷⣽⢞⣯⠾⣽⢶⣻⣭⢷⡯⣟⣳⣟⡿⣿⣿⣷⣤⡀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⢀⣹⡿⣯⣴⢿⡹⢶⡹⣎⡟⣶⡹⣖⢿⣿⡿⠛⠦⠀⠀⢸⡷⣏⣾⡳⣽⡺⣟⡽⣾⣭⢿⡽⣞⣷⣫⣟⡾⣽⣳⣯⣿⣿⡿⠿⠛⠛⠲⠀⠀⠀⠀
                        ⣾⣤⡶⣿⡹⣞⡵⣫⣞⣽⣣⣟⣵⣻⠷⣟⡾⣭⢿⣿⣦⡀⠀⠀⢸⡿⣽⢶⣻⣳⢿⣹⡽⣶⢯⣟⡾⣿⡷⣟⣾⣽⣳⣿⣿⠟⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠻⣷⣝⡶⠟⣳⡿⠋⠉⠀⠈⠉⠛⡿⣸⢻⣽⡞⣯⣿⡿⣷⠀⠀⣿⢿⡽⣞⡷⣯⣟⣷⣻⣽⣻⢾⣽⣻⢿⣜⢿⣾⣿⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠘⠻⣤⣾⡟⠀⠀⠀⠀⠀⠀⣀⣴⣿⢸⣿⣽⡳⣿⣷⡌⠁⣰⣿⢯⡿⣽⣻⣵⣻⣞⡷⣯⣟⡿⣾⣽⣻⢿⣦⠙⢿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠉⠉⠀⠀⠀⢀⣰⣾⣿⣿⢇⣿⡿⣶⢿⡿⠉⢷⢀⣿⣏⣿⣹⢷⡿⣾⢷⣏⣿⢿⣾⣿⣷⣿⣿⣿⣿⣷⠾⢿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⢀⣤⣾⣿⣿⣿⡿⣣⣿⢿⡽⣯⢿⡇⠀⣠⣿⣟⣾⣳⣯⢿⣽⢯⣟⣯⣿⡟⣿⣿⣿⣿⠿⠿⠿⣿⣷⣅⠓⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⢀⣶⣿⣿⣿⣿⡿⣫⣾⢿⡽⣯⢿⡽⣿⣠⣼⣿⣻⢾⣳⣯⣿⣟⣾⣟⣯⣿⣽⣷⢻⡿⠋⠀⠀⠀⠀⠀⠉⠙⢷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⣰⣿⣿⣿⣿⡿⣫⣾⡿⣯⢿⡽⣯⢿⣽⣿⣿⣻⢷⣻⣟⣯⣿⢻⣿⣷⣻⣟⣾⣿⣿⠸⠂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⢰⣿⣿⣿⣿⢏⣾⣿⢯⣿⡽⣯⣿⣻⣟⣾⣽⣾⣻⣟⣯⣿⣽⡟⢸⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⢸⣿⣿⣿⣏⣾⣿⡽⣟⣾⢿⣽⡾⣷⡿⣻⣿⣿⣿⣿⣿⣿⡟⠁⣿⠟⠋⠉⠉⠙⠻⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠈⠘⣿⣿⣿⢸⣿⣯⢿⡿⣽⡿⣯⣿⢿⣇⠉⠀⠀⠀⠀⠉⠿⠁⠀⠃⠀⠀⠀⠀⠀⠀⠘⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠹⣿⣿⢼⣿⣟⣿⣟⣿⣽⣿⣽⣿⣿⣿⣶⣶⣴⣤⣤⣤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠘⢿⣏⣿⣿⣻⣾⣟⣿⣾⢿⣾⡿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠙⠪⠿⣿⣯⣿⣟⣿⣿⣟⣿⣿⣯⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠻⠿⠯⠿⠿⠿⠿⠿⠷⠿⠿⢿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣶⣶⣿⣿⣷⣶⣶⡄⠘⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⣿⠿⠿⠿⠿⣿⡿⢀⣿⣿⣿⣿⡿⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⠁⠀⠀⠀⠀⠀⠀⣠⣾⣿⣿⣿⡿⠁⣼⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⣿⣿⣿⣷⣶⣤⣤⣤⣶⣿⣿⣿⣿⣿⠟⠁⠸⣿⣿⣷⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⠁⠀⠀⠀⠈⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠛⠿⠿⠿⠿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠘⣿⣿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣦⡄⢹⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣿⣿⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⠏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣼⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
                        ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀
 ██████████                                                        █████████                      ███             █████   
░░███░░░░███                                                      ███░░░░░███                    ░░░             ░░███    
 ░███   ░░███ ████████   ██████    ███████  ██████  ████████     ░███    ░░░   ██████  ████████  ████  ████████  ███████  
 ░███    ░███░░███░░███ ░░░░░███  ███░░███ ███░░███░░███░░███    ░░█████████  ███░░███░░███░░███░░███ ░░███░░███░░░███░   
 ░███    ░███ ░███ ░░░   ███████ ░███ ░███░███ ░███ ░███ ░███     ░░░░░░░░███░███ ░░░  ░███ ░░░  ░███  ░███ ░███  ░███    
 ░███    ███  ░███      ███░░███ ░███ ░███░███ ░███ ░███ ░███     ███    ░███░███  ███ ░███      ░███  ░███ ░███  ░███ ███
 ██████████   █████    ░░████████░░███████░░██████  ████ █████   ░░█████████ ░░██████  █████     █████ ░███████   ░░█████ 
░░░░░░░░░░   ░░░░░      ░░░░░░░░  ░░░░░███ ░░░░░░  ░░░░ ░░░░░     ░░░░░░░░░   ░░░░░░  ░░░░░     ░░░░░  ░███░░░     ░░░░░  
Because Dragons are cool.         ███ ░███                                                             ░███               
                                 ░░██████                                                              █████              
                                  ░░░░░░                                                              ░░░░░               "

    echo "$dragon_image"
    echo "1) Run Package Maintenance"
    echo "2) Check File Integrity"
    echo "3) Audit Permissions"
    echo "4) Audit User Accounts"
    echo "5) Secure Firewall"
    echo "6) Exit"
    read -r -p "Select an option: " option

    # Case statement to select an option by calling the respective function
    case $option in
    1) audit_packages ;;
    2) check_file_integrity ;;
    3) audit_permissions ;;
    4) audit_users ;;
    5) initiate_firwall ;;
    6)
        echo "Exiting..."
        break
        ;;
    *) echo "Invalid option. Please try again." ;;
    esac
done
