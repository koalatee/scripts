#!/bin/bash

###
#
#            Name:  add-securetoken-to-logged-in-user.sh
#     Description:  Adds SecureToken to currently logged-in user, allowing that
#                   user to unlock FileVault in macOS High Sierra. Uses
#                   credentials from a GUI-created admin account $guiAdmin
#                   (retrieves from a manually-created System keychain entry),
#                   and prompts for current user's password.
#                   https://github.com/mpanighetti/add-securetoken-to-logged-in-user
#          Author:  Mario Panighetti
#         Created:  2017-10-04
#   Last Modified:  2017-10-04
#         Version:  1.0
#
###

###
#
#       Changed by: jjourney 10/6/2017
#          changes: Changed password prompt / check to match the code in 
#                   Elliot Jordan <elliot@elliotjordan.com> FileVault key upload script
#                   https://github.com/homebysix/jss-filevault-reissue
#                   Set the guiAdmin
#
###

###
#
#       Changed by: jjourney 2/2018
#          changes: Code re-arranged for better logic due to changes
#                   Updated secureToken code because it now(?) requires auth or interactive
#                   Adds user to filevault
#                   Run "sudo diskutil apfs updatePreboot /" at the end 
#
###

###
#
#       Changed by: jjourney 08/2018
#          changes: guiAdmin now gives you the current users that already have secureToken
#                   via diskutil apfs listUsers /
#                   Removed jamfhelper and applescript confusion
#                   Added all osascript functions, should be easier to read
#                   Can now be used for both HFS / APFS 
#
###

###
#
#       Changed by: jjourney 11/2018
#          changes: changed how to get cryptousers and processing the GUIDs
#                   accounts for users over 8 char and some 10.14(?) issues
#
###

###
#
#            Setup: Fill in relevant IT + FORGOT_PW_MESSAGE
#                   Only jamf relevant piece is line 446, calls a policy to make current user admin, jamf not necessary
#
###

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

########## variables ##########
# you can edit these
PROMPT_TITLE="Password Needed For FileVault"
IT=""
FORGOT_PW_MESSAGE="You made five incorrect password attempts.
Please contact $IT."
adminfix="" 

# leave these values as-is
loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
loggedInUserFull=$(id -F $loggedInUser)
jamfBin="/usr/local/jamf/bin/jamf"

########## function-ing ##########
# get password for admin that has secure token
getPassword_guiAdminAPFS () {
    allusers=()
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
    for item in $allusers
    do
        arrayChoice+=$"${item}\n"
    done
    arrayChoice=$(echo $arrayChoice |sed 's/..$//')

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
    echo "Prompting $guiAdminPass for their Mac password..."
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
getPassword_guiAdminHFS () {
    arrayChoice=()
    # already got the $cryptousers
    fvusers=$(fdesetup list |awk -F, '{print $1}')
    for users in $fvusers
    do
        arrayChoice+=$"${users}\n"
    done
    # make it nice for applescript
    arrayChoice=$(echo $arrayChoice |sed 's/..$//')

    # Let's-a go!
    guiAdmin="$(listChoice \
        "Please select a user account with that you know the password to:" \
        "Select Existing Filevault User" \
        "Cancel" \
        "OK" \
        $arrayChoice)"
    if [[ "$guiAdmin" =~ "false" ]]; then
        echo "Cancelled by user"
        exit 0
    fi
    # Get the $guiAdmin password via a prompt.
    echo "Prompting for $guiAdminPass Mac password..."
    guiAdminPass="$(hiddenInputNoCancel \
        "Please enter the password for $guiAdmin:" \
        "$PROMPT_TITLE" \
        "OK")"
        
    # Thanks to James Barclay (@futureimperfect) for this password validation loop.
    TRY=1
    until /usr/bin/dscl /Search -authonly "$guiAdmin" "$guiAdminPass" &>/dev/null; do
        (( TRY++ ))
        echo "Prompting for $guiAdmin Mac password (attempt $TRY)..."
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
# get password for currently logged on user
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
# add SecureToken to $loggedInUser account to allow FileVault access
securetoken_add () {
    sudo sysadminctl \
        -adminUser "$guiAdmin" \
        -adminPassword "$guiAdminPass" \
        -secureTokenOn "$loggedInUser" \
        -password "$loggedInUserPass"
}
# Make sure user has secure token
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
# display success message
securetoken_success () {
    echo "✅ Verified SecureToken is enabled for $loggedInUser."
    echo "Displaying \"success\" message..."
    OneButtonInfoBox \
        "SecureToken is now set to 'Enabled' for $loggedInUser." \
        "Success!" \
        "OK"
}
# add user to filevault APFS
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
# add user to filevault HFS+
adduser_filevaultHFS () {
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
}

# make sure user is admin
# assumes it's bound to AD
$jamfBin policy -event $adminfix

########## main process ##########
cryptousers=$(diskutil apfs listusers / |awk '/\+--/ {print $NF}')

OneButtonInfoBox \
	"If there is not an account on the next screen that you know the password to, please contact $IT for assistance." \
    "Warning" \
    "OK"

# check if actually apfs disk or not
if [[ -z "$cryptousers" ]]; then
    getPassword_guiAdminHFS
    getPassword_loggedInUser
    adduser_filevaultHFS
    unset loggedInUserPass
    unset guiAdminPass
else
    getPassword_guiAdminAPFS
    getPassword_loggedInUser

    secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$loggedInUser" 2>&1)

    # add SecureToken to $loggedInUser if missing
    if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
        securetoken_add
        securetoken_double_check
        adduser_filevaultAPFS
        elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
            securetoken_success
            adduser_filevaultAPFS
        else
            echo "Error with sysadminctl"
            OneButtonInfoBox \
                "Failure to run. Please contact $IT" \
                "Failure" \
                "OK" &
    fi

    # Clear password variable.
    unset loggedInUserPass
    unset guiAdminPass
fi
exit 0
