#!/bin/bash

# jjourney 01/2018
# script to give users notification about updating apps 
# primarily about patching Spectre, with Firefox and Chrome

# jamf parameters
my_app="${4}"
app_friendly="${5}"
trigger="${6}"
full_app="/Applications/$my_app"

# local parameters
jamfBin=$(which jamf)
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
warningicon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
description="$app_friendly is out of date and the newest version contains important security updates. 

Press update to quit $app_friendly and install the new version, or press later to be notified at a later time.

Please contact IT with any questions." 

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
            $jamfBin policy -event "$trigger" 
            open "$full_app"
        elif [[ "$User_Choice" = "2" ]]; then
            echo "User said later"
    fi
fi

exit 0
