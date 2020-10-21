#!/bin/zsh

# get list of current cryptousers
#  - get pw of selected user that is admin
# input new username
# input new password
# create user, grant token, add to filevault 
#  - block login ability
# sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool YES

# variables
PROMPT_TITLE="Password Needed For FileVault"
$IT=""
FORGOT_PW_MESSAGE="You made five incorrect password attempts.
Please contact $IT for assistance."

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

###### DO NOT CHANGE BELOW THIS ######
# leave these values as-is
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
loggedInUserFull=$(id -F $loggedInUser)
# Get information necessary to display messages in the current user's context.
USER_ID=$(/usr/bin/id -u "$loggedInUser")
L_ID=$USER_ID
L_METHOD="asuser"
cryptooutput=("${(@f)$(diskutil apfs listusers /)}")
cryptousers=()
for line in $cryptooutput
do
    if [[ $(echo $line) =~ "-" ]]; then
        cryptousers+=${line:4}
    fi
done
adminGroupMembership=$(dscl . -read /Groups/admin |grep GroupMembership)

# put the users in the thing
allusers=()
arrayChoice=()
# already got the $cryptousers
for guid in $cryptousers
do
    usercheck=$(dscl . -search /Users GeneratedUID $guid \
        | awk 'NR == 1' \
        | awk '{print $1}')
        if [[ ! -z $usercheck ]]; then
        # make sure the account you're going to use is an admin
            if [[ $adminGroupMembership =~ $usercheck ]]; then
                allusers+=($usercheck)
                echo "adding $usercheck"
            else
                echo "$usercheck is a non-admin secure token holder"
            fi
        fi
done

# just zsh things
arrayChoice=$(for item in $allusers
do
    echo $item
done )

getPassword_guiAdminAPFS () {
    # Let's-a go!
    guiAdmin="$(listChoice \
        "Please select an admin user with secure token that you know the password to:" \
        "Select SecureToken User" \
        "Cancel" \
        "OK" \
        $arrayChoice )"
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

#  run it
OneButtonInfoBox \
    "This policy creates the user you want. If you have already created the user account, please use a different name or cancel the policy and delete the account." \
    "Warning" \
    "OK"

getPassword_guiAdminAPFS
createAccount
secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$newUser" 2>&1)

# add SecureToken to new account if missing
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

OneButtonInfoBox \
    "All done. You can now bypass filevault with the created account." \
    "Complete" \
    "OK" &
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableFDEAutoLogin -bool YES
