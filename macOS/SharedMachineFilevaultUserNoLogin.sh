#!/bin/sh

# script purpose:
# This uses admin input to set up a standard account that has no login ability but can unlock filevault. 
# Once filevault is bypassed the user can sign in at login window
# Helpful if you need filevault enabled in a shared space but don't want to enable every user for filevault.

# this script will:
# get list of current cryptousers
# get pw of selected user
# input new username
# input new password
# create user, grant token, add to filevault 
#      block login ability
# sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool YES

########### SETUP ##############
#
#     fill in any info below
#     run script, see above for what this does
#
################################

# things you can setup
PROMPT_TITLE="Password Needed For FileVault"
FORGOT_PW_MESSAGE="You made five incorrect password attempts."
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

cryptousers=$(diskutil apfs listusers / |awk '/\+--/ {print $NF}')

# for APFS
getPassword_guiAdminAPFS () {
    allusers=()
    arrayChoice=()
    # already got the $cryptousers
    for GUID in $cryptousers
    do
        usercheck=$(dscl . -search /Users GeneratedUID $GUID \
        | awk 'NR == 1' \
        | awk '{print $1}')
        if [[ ! -z $usercheck ]]; then
            echo $usercheck
            allusers+=($usercheck)
        fi
    done
    # make it nice for applescript
    if [[ "echo ${#allusers[@]}" > 1 ]]; then
        for item in ${allusers[@]}
        do
            arrayChoice+=$"${item}\n"
        done
        arrayChoice=${arrayChoice%??}
    else
        arrayChoice=$allusers
    fi

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
# if system is HFS still
getPassword_guiAdminHFS () {
	loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
    arrayChoice=()
    # already got the $cryptousers
    fvusers=$(fdesetup list |awk -F, '{print $1}')
    if [[ ! $fvusers == $loggedInUser ]]; then
        for users in $fvusers
        do
            arrayChoice+=$"${users}\n"
        done
        # make it nice for applescript
        arrayChoice=${arrayChoice%??}
    else
        arrayChoice=$fvusers
    fi
    
    echo "$arrayChoice users found"

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
            echo "This is the password: $guiAdminPass"
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

# add user to filevault APFS
adduser_filevaultAPFS () {
    echo "Checking Filevault status for $newUser"
    filevault_list=$(sudo fdesetup list 2>&1)
    if [[ ! "$filevault_list" =~ "$newUser" ]]; then
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
                    <string>'$newUser'</string>
                    <key>Password</key>
                    <string>'$newUserPass'</string>
                </dict>
            </array>
            </dict>
            </plist>' > /tmp/fvenable.plist 

        # now enable FileVault
        fdesetup add -inputplist < /tmp/fvenable.plist
        rm -rf /tmp/fvenable.plist

        filevault_list=$(sudo fdesetup list 2>&1)
        if [[ ! "$filevault_list" =~ "$newUser" ]]; then
            echo "Error adding user!"
            OneButtonInfoBox \
                "Failed to add $newUser to filevault. Please try to add manually." \
                "Failed to add" \
                "OK" &
        elif [[ "$filevault_list" =~ "$newUser" ]]; then
            echo "Success adding user!"
            OneButtonInfoBox \
                "Succeeded in adding $newUser to filevault." \
                "Success!" \
                "OK" &
        fi
    elif [[ "$filevault_list" =~ "$newUser" ]]; then
        echo "Success adding user!"
        OneButtonInfoBox \
            "$newUser is a filevault enabled user." \
            "Success!" \
            "OK" &
    fi

    # run updatePreboot to show user
    sudo diskutil apfs updatePreboot /
}
# add user to filevault HFS+
adduser_filevaultHFS () {
    echo "Checking Filevault status for $newUser"
    filevault_list=$(sudo fdesetup list 2>&1)
    if [[ ! "$filevault_list" =~ "$newUser" ]]; then
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
                    <string>'$newUser'</string>
                    <key>Password</key>
                    <string>'$newUserPass'</string>
                </dict>
            </array>
            </dict>
            </plist>' > /tmp/fvenable.plist 

        # now enable FileVault
        fdesetup add -inputplist < /tmp/fvenable.plist
        rm -rf /tmp/fvenable.plist
        
        filevault_list=$(sudo fdesetup list 2>&1)
        if [[ ! "$filevault_list" =~ "$newUser" ]]; then
            echo "Error adding user!"
            OneButtonInfoBox \
                "Failed to add $newUser to filevault. Please try to add manually." \
                "Failed to add" \
                "OK" &
            elif [[ "$filevault_list" =~ "$newUser" ]]; then
            echo "Success adding user!"
            OneButtonInfoBox \
                "Succeeded in adding $newUser to filevault." \
                "Success!" \
                "OK" &
        fi
        elif [[ "$filevault_list" =~ "$newUser" ]]; then
        echo "Success adding user!"
        OneButtonInfoBox \
            "$newUser is a filevault enabled user." \
            "Success!" \
            "OK" &
    fi
}

# add SecureToken to $loggedInUser account to allow FileVault access
securetoken_add () {
    sudo sysadminctl \
        -adminUser "$guiAdmin" \
        -adminPassword "$guiAdminPass" \
        -secureTokenOn "$newUser" \
        -password "$newUserPass"
}

createAccount () {
    # user prompt
    newUser="$(simpleInput \
        "Please enter the username of the shared user account (to bypass filevault):" \
        "Enter Username" \
        "Cancel" \
        "OK" )"
    # pw prompt
    newUserPass="$(hiddenInputNoCancel \
        "Please enter the password you want for $newUser (note, there is no confirmation so make sure it's correct :)):" \
        "Enter Password" \
        "OK")"

    lastID=$(dscl . -list /Users UniqueID |awk '$2 < 1000 {print $2}' |sort -n |tail -1)
    newID=($lastID + 1)
    
    dscl . -create /Users/$newUser
    dscl . -create /Users/$newUser RealName "$newUser"
    dscl . -create /Users/$newUser UniqueID $newID
    dscl . -passwd /Users/$newUser "$newUserPass"
}

# check if actually apfs disk or not
if [[ -z "$cryptousers" ]]; then
    getPassword_guiAdminHFS
    createAccount
    adduser_filevaultHFS
    unset newUserPass
    unset guiAdminPass
else
    getPassword_guiAdminAPFS
    createAccount
    secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$newUser" 2>&1)

    # add SecureToken to $loggedInUser if missing
    if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
        securetoken_add
        securetoken_double_check
        adduser_filevaultAPFS
        elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
            adduser_filevaultAPFS
        else
            echo "Error with sysadminctl"
            OneButtonInfoBox \
                "Failure to run. Please contact $IT" \
                "Failure" \
                "OK" &
    fi

    # Clear password variable.
    unset newUserPass
    unset guiAdminPass
fi

OneButtonInfoBox \
    "All done. You can now bypass filevault with the created account." \
    "Complete" \
    "OK" &

sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool YES
