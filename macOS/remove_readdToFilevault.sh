#!/bin/bash

#### SETUP INSTRUCTIONS ####
# 
#     Fill out the below messages for deployment
#     Run script for logged in user when there filevault password problems
#       - Fine to be run from jamf
#
#     Script will:
#       - prompt to pick an account with token 
#       - get that account's password
#       - get current user's password
#       - remove current user from filevault
#       - remove securetoken from current user
#       - re-add securetoken to current user
#       - re-add current user to filevault
#
#######################

PROMPT_TITLE=""
FORGOT_PW_MESSAGE=""
IT=""

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

function hiddenInputNoCancel() {
osascript <<EOT
tell app "System Events" 
with timeout of 86400 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function OneButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function TwoButtonInfoBox() {
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

# leave these values as-is
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
loggedInUserFull=$(id -F $loggedInUser)
# Get information necessary to display messages in the current user's context.
USER_ID=$(/usr/bin/id -u "$loggedInUser")
L_ID=$USER_ID
L_METHOD="asuser"
cryptousers=$(diskutil apfs listusers / |awk '/\+--/ {print $NF}')

########## function-ing ##########
# get passwords
getPassword_guiAdminAPFS () {
    allusers=()
    arrayChoice=()
    # already got the $cryptousers
    for GUID in $cryptousers
    do
        usercheck=$(sudo dscl . -search /Users GeneratedUID $GUID \
        | awk 'NR == 1' \
        | awk '{print $1}')
        if [[ ! -z $usercheck ]]; then
            echo $usercheck
            allusers+=($usercheck)
        fi
    done
    # make it nice for applescript
    for item in ${allusers[@]}
    do
        arrayChoice+=$"${item}\n"
    done
    arrayChoice=${arrayChoice%??}

    # Let's-a go!
    guiAdmin="$(listChoice \
        "Please select a user with secure token that you know the password to:" \
        "Select SecureToken User" \
        "Cancel" \
        "OK" \
        $arrayChoice)"
    if [[ "$guiAdmin" =~ "false" ]]; then
        echo "Cancelled by user"
        exit 0
    fi
    # Get the $guiAdmin password via a prompt.
    echo "Prompting $guiAdmin for their Mac password..."
    guiAdminPass="$(hiddenInputNoCancel \
        "Please enter the password for $guiAdmin:" \
        "$PROMPT_TITLE" \
        "OK")"
        
    # Thanks to James Barclay (@futureimperfect) for this password validation loop.
    TRY=1
    until /usr/bin/dscl /Search -authonly "$guiAdmin" "$guiAdminPass" &>/dev/null; do
        (( TRY++ ))
        echo "Prompting $guiAdmin for their Mac password (attempt $TRY)..."
        guiAdminPass="$(hiddenInput \
            "Sorry, that password was incorrect. Please try again:" \
            "$PROMPT_TITLE" \
            "Cancel" \
            "OK" )"
            if [[ "$guiAdminPass" =~ "false" ]] || [[ -z "$guiAdminPass" ]]; then
                exit 0
            fi
        if (( TRY >= 5 )); then
            echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
            OneButtonInfoBox \
                "$FORGOT_PW_MESSAGE" \
                "$PROMPT_TITLE" \
                "OK" &
            exit 1
        fi
    done
    echo "Successfully prompted for $guiAdmin password."
}
getPassword_loggedInUser () {
    # Get the logged in user's password via a prompt.
    echo "Prompting $loggedInUser for their Mac password..."
    loggedInUserPass="$(hiddenInputNoCancel \
        "Please enter the password for $loggedInUserFull, the one used to log in to this Mac:" \
        "Password needed for Filevault" \
        "OK")"
    # Thanks to James Barclay (@futureimperfect) for this password validation loop.
    TRY=1
    until /usr/bin/dscl /Search -authonly "$loggedInUser" "$loggedInUserPass" &>/dev/null; do
        (( TRY++ ))
        echo "Prompting $loggedInUser for their Mac password (attempt $TRY)..."
        loggedInUserPass="$(hiddenInput \
            "Sorry, that password was incorrect. Please try again:" \
            "$PROMPT_TITLE" \
            "Cancel" \
            "OK")"
            if [[ "$loggedInUserPass" =~ "false" ]] || [[ -z "$loggedInUserPass" ]]; then
                exit 0
            fi
        if (( TRY >= 5 )); then
            echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
            OneButtonInfoBox \
                "$FORGOT_PW_MESSAGE" \
                "$PROMPT_TITLE" \
                "OK" &
            exit 1
        fi
    done
    echo "Successfully prompted for $loggedInUser password."
}

# removal the old
filevault_remove () {
	fdesetup remove -user $loggedInUser
}
securetoken_removal () {
	sysadminctl -secureTokenOff "$loggedInUser" \
	-password "$loggedInUserPass" \
	-adminUser "$guiAdmin" \
	-adminPassword "$guiAdminPass"
}

# additions
securetoken_add () {
    sudo sysadminctl \
    -adminUser "$guiAdmin" \
    -adminPassword "$guiAdminPass" \
    -secureTokenOn "$loggedInUser" \
    -password "$loggedInUserPass"
}
adduser_filevaultAPFS () {
    echo "Checking Filevault status for $loggedInUser"
    filevault_list=$(sudo fdesetup list 2>&1)
    if [[ ! "$filevault_list" =~ "$loggedInUser" ]]; then
        echo "User not found, adding"
        # create the plist file:
        echo '<?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            <key>Username</key>
            <string>'$guiAdmin'</string>
            <key>Password</key>
            <string>'$guiAdminPass'</string>
            <key>AdditionalUsers</key>
            <array>
                <dict>
                    <key>Username</key>
                    <string>'$loggedInUser'</string>
                    <key>Password</key>
                    <string>'$loggedInUserPass'</string>
                </dict>
            </array>
            </dict>
            </plist>' > /tmp/fvenable.plist 

        # now enable FileVault
        fdesetup add -inputplist < /tmp/fvenable.plist
        rm -rf /tmp/fvenable.plist

        filevault_list=$(sudo fdesetup list 2>&1)
        if [[ ! "$filevault_list" =~ "$loggedInUser" ]]; then
            echo "Error adding user!"
            OneButtonInfoBox \
                "Failed to add $loggedInUserFull to filevault. Please try to add manually." \
                "Failed to add" \
                "OK" &
        elif [[ "$filevault_list" =~ "$loggedInUser" ]]; then
            echo "Success adding user!"
            OneButtonInfoBox \
                "Succeeded in adding $loggedInUserFull to filevault." \
                "Success!" \
                "OK" &
        fi
    elif [[ "$filevault_list" =~ "$loggedInUser" ]]; then
        echo "Success adding user!"
        OneButtonInfoBox \
            "$loggedInUserFull is a filevault enabled user." \
            "Success!" \
            "OK" &
    fi

    # run updatePreboot to show user
    sudo diskutil apfs updatePreboot /
}

# clean-up and success
securetoken_double_check () {
    secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$loggedInUser" 2>&1)
    if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
        echo "❌ ERROR: Failed to add SecureToken to $loggedInUser for FileVault access."
        echo "Displaying \"failure\" message..."
        OneButtonInfoBox \
            "Failed to set SecureToken for $loggedInUser. Status is $secureTokenCheck. Please contact $IT." \
            "Failure" \
            "OK" &
        exit 1
    elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
        securetoken_success
    else
        echo "???unknown error???"
        exit 3
    fi
}
securetoken_success () {
    echo "✅ Verified SecureToken is enabled for $loggedInUser."
    echo "Displaying \"success\" message..."
    OneButtonInfoBox \
        "SecureToken is now set to 'Enabled' for $loggedInUser." \
        "Success!" \
        "OK"
}

confirmation=$(TwoButtonInfoBox \
    "Make sure you are not trying to modify the only SecureToken User, or it may break." \
    "WARNING" \
    "Cancel" \
    "OK")
if [[ -z "$confirmation" ]]; then
    echo "exiting"
    exit 0
fi

# with our powers combined....
getPassword_guiAdminAPFS
getPassword_loggedInUser
# Remove the user from filevault:
# - fdesetup remove -user {USERNAME}
filevault_remove
# Now remove the token: 
# - Sysadminctl interactive -secureTokenOff {USERNAME} -password 
securetoken_removal
# Now turn it back on:
# - Sysadminctl interactive -secureTokenOn {USERNAME} -password 
securetoken_add
# Should automatically be added to filevault, check with:
# Run this command to make sure the user shows up in the filevault list 
# - diskutil apfs updatePreboot /
securetoken_double_check
adduser_filevaultAPFS

unset loggedInUserPass
unset guiAdminPass
