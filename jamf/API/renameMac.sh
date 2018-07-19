#!/bin/bash

# Rename Mac through Self Service Policy

###### Variables ######
# System
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# jamf
jamf="" # yours goes here
triggername="" # this is for a policy to force jamf name

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '' '') # input values here - https://github.com/jamfit/Encrypted-Script-Parameters
apiPass=$(DecryptString $5 '' '') # input values here - https://github.com/jamfit/Encrypted-Script-Parameters

# applescript
#
# template:
########### Title - "$2" ############
#                                   #
#     Text to display - "$1"        #
#                                   #
#      [Default response - "$5"]    #
#                                   #
#               (B1 "$3") (B2 "$4") # <- Button 2 default
#####################################

function simpleInput() {
osascript <<EOT
tell app "System Events" 
with timeout of 86400 seconds
text returned of (display dialog "$1" default answer "$5" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function hiddenInput() {
osascript <<EOT
tell app "System Events" 
with timeout of 86400 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function 1ButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function 2ButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
button returned of (display dialog "$1" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function listChoice() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
choose from list every paragraph of "$5" with title "$2" with prompt "$1" OK button name "$4" cancel button name "$3"
end timeout
end tell
EOT
}

#### changing computer name ######
# ask if user wants to change it
computerName_prompt="$(2ButtonInfoBox \
    "The current name is $computerName. Would you like to change it?" \
    "Computer Name" \
    "Cancel" \
    "OK")"
if [[ "$computerName_prompt" != "OK" ]]; then
    exit 0
fi

# Prompts if the user says yes
if [[ "$computerName_prompt" =~ "OK" ]]; then
    oldName="$(curl \
        -s \
        -f \
        -u "$apiUser:$apiPass" \
        -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
        -H "Accept: application/xml" \
        | xpath //computer/general/name[1] \
        | sed -e 's/<name>//;s/<\/name>//' \
        )"
    # if yes, continue
    if [ -z "$oldName" ]; then
        error_full="$(2ButtonInfoBox \
            "There seems to be an issue connecting to jamf. Please try again" \
            "Error" \
            "Cancel" \
            "OK")"
        exit 1
    else
        # Enter new computer name
        newComputerName="$(simpleInput \
            "Please enter the new name:" \
            "New Name" \
            "Cancel" \
            "OK" \
            "$oldName")"
        if [[ "$?" != 0 ]]; then
            exit 0
        fi
        # Make sure there is no space (" ") 
        pattern=" |'"
        while [[ -z "$newComputerName" || "$newComputerName" =~ $pattern ]]
            do
            newComputerName="$(simpleInput \
                "Please enter the new name:" \
                "New Name" \
                "Cancel" \
                "OK" \
                "$oldName")"
            if [[ "$?" != 0 ]]; then
                exit 0
            fi
        done

        # set apiData
        apiData="<computer><general><name>$newComputerName</name></general></computer>"

        # Final PUT command, updating new Name
        curl \
            -s \
            -f \
            -u "$apiUser:$apiPass" \
            -X PUT \
            -H "Content-Type: text/xml" \
            -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jamf/JSSResource/computers/serialnumber/$serialNumber
    
        # Change variable
        computerName="$newComputerName"
    
        # Run policy to have it update
        sudo jamf policy -trigger $triggername

        # New Check
        checkName="$(curl \
            -s \
            -f \
            -u "$apiUser:$apiPass" \
            -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
            -H "Accept: application/xml" \
            | xpath //computer/general/name[1] \
            | sed -e 's/<name>//;s/<\/name>//' \
            )"

        # Display newest Name
        1ButtonInfoBox \
            "The new name is $checkName" \
            "Computer Name" \
            "OK"
    fi
fi

exit 0
