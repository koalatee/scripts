#!/bin/zsh

# jjourney 12-2018
# try and help with updating fv password if they are out of sync

# essentially runs the following command:
# diskutil apfs changePassphrase $disk -user $GUID -oldPassphrase $oldPW -newPassphrase $currentPW

# error messages
IT=""
CONTACT_IT="Something went wrong when trying to change your password. Please try again or contact $IT for further assistance"
NEW_PASSWORD_MESSAGE="Please enter your new password:"
OLD_PASSWORD_MESSAGE="Please enter the old password (the one that currently works to unlock Filevault):"
INCORRECT_PASSWORD_MESSAGE="Sorry, that password was incorrect. Please try again:"
SUCCESS_MESSAGE="Your filevault password has been successfully updated. Please contact $IT if you have any more problems"

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

# get GUID of token users
cryptooutput=("${(@f)$(diskutil apfs listusers /)}")
cryptousers=()
for line in $cryptooutput
do
    if [[ $(echo $line) =~ "-" ]]; then
        cryptousers+=${line:4}
    fi
done

allusers=()
arrayChoice=()
# already got the $cryptousers
for guid in $cryptousers
do
    usercheck=$(dscl . -search /Users GeneratedUID $guid \
        | awk 'NR == 1' \
        | awk '{print $1}')
        if [[ ! -z $usercheck ]]; then
            allusers+=($usercheck)
        fi
done
    
arrayChoice=$(for item in $allusers
do
    echo $item
done )

# Let's-a go!
# apparently doing lists first doesn't work in 10.15 catalina
OneButtonInfoBox \
	"If this does not work, please reach out to RTS for assistance to resolve." \
    "Warning" \
    "OK"
    
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
    
# clear variables
unset oldPassword
unset newPassword
