#!/bin/sh

# Used in conjunction with (script creates) the following:
# /Library/LaunchDaemons/com.$company.appleUpdates.plist
# /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist
# /Library/$company/Scripts/loadAppleUpdatesLD.sh
#
# Runs Apple Updates in background
# Prompts user to restart for updates that require a restart
# jjourney 05/2016
# Works on OSX version 10.9.x, 10.10.x, and 10.11.x 
# Mostly pulled from https://jamfnation.jamfsoftware.com/discussion.html?id=7827

# 03/2017 UPDATE - added better checking for installing updates. Updates are now cached and "recommended" are 
# automatically installed. The user is then prompted for ones that require a restart. Installs by name so 
# the delay between pressing the 'restart now' button and the actual restart is much quicker.

# Logging location
log_location="/var/log/appleUpdater.log"
ScriptLogging(){

    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    LOG="$log_location"
    
    echo "$DATE" " $1" >> $LOG
}

osvers=$(sw_vers -productVersion | awk -F. '{print $2}')
# Exit if OS version not high enough
if [[ $osvers -lt 9 ]]; then
    ScriptLogging "Script only for 10.9+ only"
    exit 1
fi

jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
# Create recurring updater
##################################################################################
# Create file if not exist

# Get date values
currentDay=$(date +%d)
currentHour=$(date +%k)
add10Minute=$(date -v+10M +%M)
# Fix issues if script is run between :50-:59
if [ $add10Minute -lt 10 ]; then
add10Minute=$(date +%M);
fi

if [[ ! -f /Library/LaunchDaemons/com.$company.appleUpdates.plist ]]; then
ScriptLogging "Creating appleUpdates.plist"
cat > /Library/LaunchDaemons/com.$company.appleUpdates.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.$company.appleUpdates</string>
	<key>ProgramArguments</key>
	<array>
		<string>sh</string>
		<string>/Library/$company/Scripts/AppleUpdates.sh</string>
	</array>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Day</key>
		<integer>$currentDay</integer>
		<key>Hour</key>
		<integer>$currentHour</integer>
		<key>Minute</key>
		<integer>$add10Minute</integer>
	</dict>
</dict>
</plist>
EOF

# Edit file if exist (runs monthly)
elif [[ -f /Library/LaunchDaemons/com.$company.appleUpdates.plist ]]; then
mainplist=/Library/LaunchDaemons/com.$company.appleUpdates.plist
ScriptLogging "Editing $mainplist with new values."
       sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $currentDay" $mainplist
       sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour $currentHour" $mainplist
       sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Minute $add10Minute" $mainplist
fi

# Create plist to run a script that opens this plist :D
##################################################################################
# Delete and create again (runs monthly)
if [[ ! -f /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist ]]; then

# Create launchd to run script
ScriptLogging "Creating loadAppleUpdates.plist"
cat > /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.$company.loadAppleUpdates</string>
	<key>ProgramArguments</key>
	<array>
		<string>sh</string>
		<string>/Library/$company/Scripts/loadAppleUpdatesLD.sh</string>
	</array>
	<key>StartInterval</key>
	<integer>30</integer>
</dict>
</plist>
EOF

fi

# Do not load this now. 
# loops.
##################################################################################

# Create script to load the other plist :D
##################################################################################
if [[ ! -d /Library/$company/Scripts ]]; then
    sudo mkdir -p /Library/$company/Scripts
    ScriptLogging "/Library/$company/Scripts created"
fi

# Delete and create again (runs monthly)
if [[ ! -f /Library/$company/Scripts/loadAppleUpdatesLD.sh ]]; then

# Create bash script that unloads/loads correct plist
ScriptLogging "Creating loadAppleUpdatesLD.sh"
cat > /Library/$company/Scripts/loadAppleUpdatesLD.sh <<'EOF'
#!/bin/bash
# 
# If loaded, this first unloads the following:
# /Library/LaunchDaemons/com.$company.appleUpdates.plist
#
# Then loads:
# /Library/LaunchDaemons/com.$company.appleUpdates.plist
#
# Called from /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist
# jjourney 05/2016

# Logging location
log_location="/var/log/appleUpdater.log"
ScriptLogging(){

    DATE=$(date +%Y-%m-%d\ %H:%M:%S)
    LOG="$log_location"
    
    echo "$DATE" " $1" >> $LOG
}

# plist values
AppleUpdates=$(sudo launchctl list |grep $company.appleUpdates)

# See if above 2 launchd are already running
if [[ $AppleUpdates =~ "com.$company.appleUpdates" ]]; then
    sudo launchctl unload /Library/LaunchDaemons/com.$company.appleUpdates.plist
    ScriptLogging "com.$company.appleUpdates.plist unloaded";
fi


# Loads the plist values and logs /var/log/appleUpdater.log
sudo launchctl load /Library/LaunchDaemons/com.$company.appleUpdates.plist
ScriptLogging "com.$company.appleUpdates.plist loaded"
ScriptLogging "com.$company.loadAppleUpdates.plist unloaded"
sudo launchctl unload /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist

ScriptLogging "oops. you messed up."
exit 0
EOF

# Make sure script has executable permissions
sudo chmod +x /Library/$company/Scripts/loadAppleUpdatesLD.sh

fi

##################################################################################
#                    Done creating plists and scripts                            #
#                              :partyparrot:                                     #
##################################################################################


ScriptLogging "======Apple Updates Starting======"

# Variables
UpdatePlist="/Library/Updates/index.plist"
DownloadCheck=$(ls /Library/Updates | grep -v .plist )
UpdateFile="/tmp/swu"
if [[ ! -f "$UpdateFile" ]]; then
    softwareupdate -l > $UpdateFile
fi
UpdateList=$(softwareupdate -l 2>&1)
UpdatesNeeded=$(echo "$UpdateList" |grep "No new software available.")
UpdatesRestart=$(echo "$UpdateList" |grep "[restart]" )
installSWUs=$(grep -v 'recommended' $UpdateFile | awk -F'\\* ' '/\*/{print $NF}')
restartSWUs=$(sed -n '/restart/{x;p;d;}; x' $UpdateFile | awk -F'\\* ' '/\*/{print $NF}')

SWUItems=()
SWURestartItems=()

# Create Array
while read swuitem; do
SWUItems+=( "$swuitem" )
done < <(echo "${installSWUs}")

# Create Array
while read swuritem; do
SWURestartItems+=( "$swuritem" )
done < <(echo "${restartSWUs}")

# Plist variables
LDWaitTime="/Library/LaunchDaemons/com.$company.appleUpdates.plist" 
StartLD="/Library/LaunchDaemons/com.$company.loadAppleUpdates.plist"
# Date variables
currentDay=$(date +%d)
currentHour=$(date +%k)
currentMinute=$(date +%M)
addTwoWeeks=$(date -v+14d +%d)
addOneDay=$(date -v+1d +%d)
addHour=$(date -v+60M +%k)
addFourHour=$(date -v+240M +%k)

grepStartLD=$(sudo launchctl list |grep $company.loadAppleUpdates)
# checks if $StartLD is running, unload it if it is
if [[ $grepStartLD =~ "com.$company.loadAppleUpdates" ]]; then
    sudo launchctl unload /Library/LaunchDaemons/com.$company.loadAppleUpdates.plist
    ScriptLogging "com.$company.loadAppleUpdates.plist unloaded"
fi

ScriptLogging "Updates available: ${installSWUs[@]}"
# Begin SoftwareUpdating
# If no new software available, script re-runs in 2 weeks
if [[ $UpdatesNeeded =~ "No new software available." ]]; then
    rm -rf "$UpdateFile"
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $addTwoWeeks" "$LDWaitTime"
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour $currentHour" "$LDWaitTime"
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Minute $currentMinute" "$LDWaitTime"
    ScriptLogging "No updates available."
    ScriptLogging "Script will re-run in 2 weeks."
    ScriptLogging "======Apple Updates Finished======"
    ScriptLogging ""
    sudo launchctl load "$StartLD"
    sudo launchctl unload "$LDWaitTime"
    ScriptLogging "Huh. How did that happen... Script run directly"
    exit 1

# Install updates that require restart
##################################################################################
elif [[ $UpdatesRestart =~ "[restart]" ]]; then
ScriptLogging "Updates available that need restart."
# Download softwareupdate files before prompting users to install/reboot
    if [[ -z $DownloadCheck ]]; then
        ScriptLogging "Downloading Updates"
        /usr/sbin/softwareupdate -da
    else
        ScriptLogging "There are updates downloaded"
    fi
    
    # Pop-up window variables for restart 
    Message=$'$company SUPPORT \n\nSoftware Updates need to be installed on your Mac that require a restart. \nYou can choose to restart now, or delay reminder for 1, 4, or 24 hours. \n------------------------------------------------------------- \n\nIf you have any questions, contact $company. \n\nDelay reminder for:'
    Message2=$'Downloading and installing updates. \nThis may take several minutes before the reboot occurs.'
    choice="0"
    options=("3600, 14400, 86400")
    TITLE="Apple Software Updates - Restart required"
    TITLE2="Installing Updates"
    MSG="$Message" 
    MSG2="$Message2"
    
    for SWU in "${SWUItems[@]}"; do
        if [[ "${SWURestartItems[@]}" =~ "$SWU" ]]; then
            ScriptLogging "skipping $SWU for now"
        else 
            ScriptLogging "Installing $SWU"
            softwareupdate --install "$SWU"
        fi
    done
    
    # Pop-up window with message
        jamfwindow="$("$jamfHelper" \
            -windowType hud \
            -alignDescription center \
            -title "$TITLE" \
            -description "$MSG" \
            -showDelayOptions "$options" \
            -button1 "Restart" \
            -button2 "Delay" \
            -defaultButton 2 \
            -lockHUD \
            )"
            
    # Re-hash dates in case this just sat for a while 
    currentDay=$(date +%d)
    currentHour=$(date +%k)
    currentMinute=$(date +%M)
    addTwoWeeks=$(date -v+14d +%d)
    addOneDay=$(date -v+1d +%d)
    addHour=$(date -v+60M +%k)
    addFourHour=$(date -v+240M +%k)
    
    # [$option][buttonpress] indicates choice
    # more jamfhelper notes here: https://gist.github.com/homebysix/18c1a07a284089e7f279
    # Delay 1 hour
    if [ $jamfwindow == "36002" ]; then
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour $addHour" "$LDWaitTime"
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $currentDay" "$LDWaitTime"
        ScriptLogging "Updates delayed for 1 hour."
        ScriptLogging "======Apple Updates Delayed======"
        ScriptLogging "";
    # Delay 4 hours
    elif [ $jamfwindow == "144002" ]; then
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour $addFourHour" "$LDWaitTime"
        # Change date if adding 4 hours changes to a new day (aka after 8pm)
        if [[ $addFourhour -lt 4 ]]; then
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $addOneDay" "$LDWaitTime"
        else
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $currentDay" "$LDWaitTime"
        fi
        # fin
        ScriptLogging "Updates delayed for 4 hours."
        ScriptLogging "======Apple Updates Delayed======"
        ScriptLogging "";
    # Delay 24 hours
    elif [ $jamfwindow == "864002" ]; then 
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $addOneDay" "$LDWaitTime"
        ScriptLogging "Updates delayed for 24 hours."
        ScriptLogging "======Apple Updates Delayed======"
        ScriptLogging "";
    # Restart now, installs updates and sets script to run in 2 weeks
    elif [ $jamfwindow == "36001" ] || [ $jamfwindow == "144001" ] || [ $jamfwindow == "864001" ]; then
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $addTwoWeeks" $LDWaitTime
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour 10" $LDWaitTime
        sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Minute 00" $LDWaitTime
        ScriptLogging "Installing updates that require restart."
        ScriptLogging "Script will re-run in 2 weeks."
        rm -rf "$UpdateFile"
    # Pop-up window with message
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "$TITLE2" \
        -description "$MSG2" \
        -button1 "OK" \
        -defaultButton 1 \
        -lockHUD

        for SWUR in "${SWUItems[@]}"; do
            ScriptLogging "Installing $SWUR"
            softwareupdate --install "$SWUR"
        done
        
        #if [ $osvers = 11 ]; then
        #    ScriptLogging "OSX10.11 installing updates already downloaded."
        #    softwareupdate -ia --no-scan;
        #else
        #    ScriptLogging "OSX10.10- downloading and installing updates."
        #    softwareupdate -ia
        #fi
        ScriptLogging "======Apple Updates Finished======"
        ScriptLogging ""
    #reboot machine
        sudo /sbin/reboot
        exit 3
        ScriptLogging "wow. you really messed up!! :partyparrot:";
    fi



# Installs updates if none require restart, script will run again in 2 weeks
##################################################################################
elif [[ $UpdateList =~ "[recommended]" ]]; then
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Day $addTwoWeeks" $LDWaitTime
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Hour 10" $LDWaitTime
    sudo /usr/libexec/PlistBuddy -c "Set :StartCalendarInterval:Minute 00" $LDWaitTime
    ScriptLogging "Recommended updates installed."
    ScriptLogging "Script will re-run in 2 weeks."
    ScriptLogging "======Apple Updates Finished======"
    ScriptLogging ""
    for SWU in "${SWUItems[@]}"; do
        if [[ "${SWURestartItems[@]}" =~ "$SWU" ]]; then
            ScriptLogging "skipping $SWUfor now"
        else 
            ScriptLogging "Installing $SWU"
            softwareupdate --install "$SWU"
        fi
    done
    
    # /usr/bin/sudo /usr/sbin/softwareupdate -ia;
    rm -rf "$UpdateFile"
fi



# Reload LaunchDaemon loadAppleUpdates.plist
sudo launchctl load "$StartLD"
sudo launchctl unload "$LDWaitTime"

exit 0
