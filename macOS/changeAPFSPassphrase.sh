#!/bin/sh

# jjourney 12-2018
# try and help with updating fv password

# diskutil apfs changePassphrase $disk -user $GUID

# error messages
CONTACT_IT=""
NEW_PASSWORD_MESSAGE=""
OLD_PASSWORD_MESSAGE=""
INCORRECT_PASSWORD_MESSAGE=""
SUCCESS_MESSAGE=""

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

function simpleInputNoCancel() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
text returned of (display dialog "$1" default answer "$4" buttons {"$3"} default button 1 with title "$2")
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

# 
cryptousers=$(diskutil apfs listusers / |awk '/\+--/ {print $NF}')
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
arrayChoice=$(echo $arrayChoice |sed 's/..$//')

# Let's-a go!
changeUser="$(listChoice \
    "Please select the user you want to update the Filevault password for:" \
    "Click To Select User" \
    "Cancel" \
    "OK" \
    $arrayChoice)"
if [[ "$changeUser" =~ "false" ]]; then
    echo "Cancelled by user"
    exit 0
fi

# Get GUID
FullGUID=$(dscl . -read /Users/$changeUser GeneratedUID)
changeUserGUID=${FullGUID#*: }

# Get passwords
oldPassword="$(hiddenInputNoCancel \
    "$OLD_PASSWORD_MESSAGE" \
    "Old Password" \
    "OK" )"

newPassword="$(hiddenInputNoCancel \
    "$NEW_PASSWORD_MESSAGE" \
    "New Password" \
    "OK" )"
    # Thanks to James Barclay (@futureimperfect) for this password validation loop.
    TRY=1
    until /usr/bin/dscl /Search -authonly "$changeUser" "$newPassword" &>/dev/null; do
        (( TRY++ ))
        newPassword="$(hiddenInput \
            "$INCORRECT_PASSWORD_MESSAGE" \
            "New Password" \
            "Cancel" \
            "OK" )"
            if [[ "$newPassword" =~ "false" ]] || [[ -z "$newPassword" ]]; then
                exit 0
            fi
        if (( TRY >= 5 )); then
        echo "error, could not validate new password"
            OneButtonInfoBox \
                "$CONTACT_IT" \
                "Error" \
                "OK" &
            unset oldPassword
            unset newPassword
            exit 1
        fi
    done

# find disk 
diskChoice=$(diskutil apfs listusers / \
    | head -n 1 \
    | sed 's/Cryptographic users for //' \
    | sed 's/ (.*$//')

diskutil apfs changePassphrase $diskChoice -user $changeUserGUID -oldPassphrase $oldPassword -newPassphrase $newPassword
if [[ $? -ne 0 ]]; then
    OneButtonInfoBox \
        "$CONTACT_IT" \
        "Error" \
        "OK" &
    unset oldPassword
    unset newPassword
    exit 1
fi

OneButtonInfoBox \
    "$SUCCESS_MESSAGE" \
    "Success!" \
    "OK" &
    
sudo diskutil apfs updatePreboot /

# clear variables
unset oldPassword
unset newPassword
