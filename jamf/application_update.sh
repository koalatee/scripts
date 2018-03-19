#!/bin/bash

# jjourney 01/2018
# script to give users notification about updating apps 
# 
# Setup: jamf parameter labels
# 4 App name - include .app
# 5 Friendly app name - (eg "Firefox" - will be displayed to user)
# 6 trigger for install - (if a user says "install" it will run this trigger)
# 7 (optional) App Helper process -  used for Reader update
# 8 Re-open app? (Yes or No) - currently must be yes or no
# 9 Open App (if app name change) - can specify if app is updating to a new name (like Reader or Acrobat pro)

# Setup: script parameters
# add IT
# add email

# Setup: other
# this script is in one policy with the labels necessary
# create a second policy with custom trigger in parameter 6

# jamf parameters
my_app="${4}"
app_friendly="${5}"
trigger="${6}"
helper="${7}"
open="${8}"
new_app="${9}"

# script parameters:
IT=""
email=""

if [[ -z "$new_app" ]]; then
    full_app="/Applications/$my_app"
else 
    full_app="/Applications/$new_app"
    old_app="/Applications/$my_app"
fi

# local parameters
jamfBin=$(which jamf)
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
warningicon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
description="$app_friendly is out of date and the newest version contains important security updates. 

Press update to quit $app_friendly and install the new version, or press later to be notified at a later time. $app_friendly will re-open when installation is complete.

Please contact IT at $email with any questions." 

if ! pgrep -f "$my_app" &>/dev/null; then
    echo "$app_friendly not running, updating now."
    $jamfBin policy -event "$trigger"
else
    User_Choice=$("$jamfHelper" \
        -windowType utility \
        -icon "$warningicon" \
        -heading "Application Update" \
        -description "$description" \
        -button1 "Update" \
        -button2 "Later" \
        -defaultButton 1)
    if [[ "$User_Choice" = "0" ]]; then
            echo "User said now"
            pkill -f "$my_app" 
            # Check if there's a helper (like Reader)
            if [[ ! -z "$7" ]]; then
                sleep 1s
                pkill -f "$helper"
            fi
            $jamfBin policy -event "$trigger" 
            # Check if this is a new app to upgrade, delete the old one if name change
            if [[ ! -z "$old_app" ]]; then
                rm -rf "$old_app"
            fi
            if [[ "$open" = "Yes" ]]; then
                open "$full_app"
            fi
        elif [[ "$User_Choice" = "2" ]]; then
            echo "User said later"
    fi
fi

exit 0
