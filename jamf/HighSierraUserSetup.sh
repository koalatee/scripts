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
#            Setup: Fill in relevant IT + FORGOT_PW_MESSAGE
#                   Default is to prompt for the guiAdmin (that has SecureToken), can input the guiAdmin user if you want
#
###

########## variable-ing ##########

# replace with username of a GUI-created admin account
# (or any admin user with SecureToken access)
guiAdmin=""
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
PROMPT_TITLE="Password Needed For FileVault"
IT=""
FORGOT_PW_MESSAGE="You made five incorrect password attempts.
Please contact $IT for assistance."

# leave these values as-is
loggedInUser=$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
loggedInUserFull=$(id -F $loggedInUser)
# Get information necessary to display messages in the current user's context.
USER_ID=$(/usr/bin/id -u "$loggedInUser")
L_ID=$USER_ID
L_METHOD="asuser"

########## function-ing ##########

if [[ -z $guiAdmin ]]; then
    # Get the $guiAdmin via a prompt
    guiAdmin="$(/bin/launchctl "$L_METHOD" "$L_ID" /usr/bin/osascript -e 'display dialog "Please enter the username of the user with Secure Token:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1' -e 'return text returned of result')"
fi
# Get the $guiAdmin password via a prompt.
echo "Prompting $guiAdminPass for their Mac password..."
guiAdminPass="$(/bin/launchctl "$L_METHOD" "$L_ID" /usr/bin/osascript -e 'display dialog "Please enter the password for '"$guiAdmin"':" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$guiAdmin" "$guiAdminPass" &>/dev/null; do
    (( TRY++ ))
    echo "Prompting $guiAdmin for their Mac password (attempt $TRY)..."
    guiAdminPass="$(/bin/launchctl "$L_METHOD" "$L_ID" /usr/bin/osascript -e 'display dialog "Sorry, that password was incorrect. Please try again:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"
    if (( TRY >= 5 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
            -windowType "utility" \
            -title "$PROMPT_TITLE" \
            -description "$FORGOT_PW_MESSAGE" \
            -button1 'OK' \
            -defaultButton 1 \
            -startlaunchd &>/dev/null &
        exit 1
    fi
done
echo "Successfully prompted for $guiAdmin password."


# add SecureToken to $loggedInUser account to allow FileVault access
securetoken_add () {
# This sample script assumes that the $guiAdmin account credentials have
# already been saved in the System keychain in an entry named "$guiAdmin".
# If you want to prompt for this information instead of pulling from the
# keychain, you can copy the below osascript to generate a new prompt, and
# pass the result to $guiAdminPass.

# Get the logged in user's password via a prompt.
echo "Prompting $loggedInUser for their Mac password..."
loggedInUserPass="$(/bin/launchctl "$L_METHOD" "$L_ID" /usr/bin/osascript -e 'display dialog "Please enter the password for '"$loggedInUserFull"', the one used to log in to this Mac:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$loggedInUser" "$loggedInUserPass" &>/dev/null; do
    (( TRY++ ))
    echo "Prompting $loggedInUser for their Mac password (attempt $TRY)..."
    $loggedInUserPass="$(/bin/launchctl "$L_METHOD" "$L_ID" /usr/bin/osascript -e 'display dialog "Sorry, that password was incorrect. Please try again:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"
    if (( TRY >= 5 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
            -windowType "utility" \
            -title "$PROMPT_TITLE" \
            -description "$FORGOT_PW_MESSAGE" \
            -button1 'OK' \
            -defaultButton 1 \
            -startlaunchd &>/dev/null &
        exit 1
    fi
done
echo "Successfully prompted for $loggedInUser password."

sudo sysadminctl \
    -adminUser "$guiAdmin" \
    -adminPassword "$guiAdminPass" \
    -secureTokenOn "$loggedInUser" \
    -password "$loggedInUserPass"
}


securetoken_double_check () {
    secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$loggedInUser" 2>&1)
    if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
        echo "❌ ERROR: Failed to add SecureToken to $loggedInUser for FileVault access."
        echo "Displaying \"failure\" message..."
        /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
            -windowType "utility" \
            -title "Failure" \
            -description "Failed to set SecureToken for $loggedInUser. Status is $secureTokenCheck. Please contact $IT." \
            -button1 'OK' \
            -defaultButton 1 \
            -startlaunchd &>/dev/null &
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
    /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
        -windowType "utility" \
        -title "Success!" \
        -description "SecureToken is now set to \"Enabled\" for $loggedInUser." \
        -button1 'OK' \
        -defaultButton 1 \
        -startlaunchd &>/dev/null
}

adduser_filevault () {
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
        fdesetup enable -inputplist < /tmp/fvenable.plist
        rm -rf /tmp/fvenable.plist

        filevault_list=$(sudo fdesetup list 2>&1)
        if [[ ! "$filevault_list" =~ "$loggedInUser" ]]; then
            echo "Error adding user!"
            /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
                -windowType "utility" \
                -title "Failed to add" \
                -description "Failed to add $loggedInUserFull to Filevault. Please try to add manually." \
                -button1 'OK' \
                -defaultButton 1 \
                -startlaunchd &>/dev/null &
        elif [[ "$filevault_list" =~ "$loggedInUser" ]]; then
            echo "Success adding user!"
            /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
                -windowType "utility" \
                -title "Success!" \
                -description "Succeeded in adding $loggedInUserFull to Filevault." \
                -button1 'OK' \
                -defaultButton 1 \
                -startlaunchd &>/dev/null &
        fi
    elif [[ "$filevault_list" =~ "$loggedInUser" ]]; then
        echo "Success adding user!"
        /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
            -windowType "utility" \
            -title "Success!" \
            -description "$loggedInUserFull is a Filevault enabled user." \
            -button1 'OK' \
            -defaultButton 1 \
            -startlaunchd &>/dev/null &
    fi

    # run updatePreboot to show user
    sudo diskutil apfs updatePreboot /
}


########## main process ##########
# Have to have user/pass before you can check for secureToken :thinking:
secureTokenCheck=$(sudo sysadminctl -adminUser $guiAdmin -adminPassword $guiAdminPass -secureTokenStatus "$loggedInUser" 2>&1)

# add SecureToken to $loggedInUser if missing
if [[ "$secureTokenCheck" =~ "DISABLED" ]]; then
    securetoken_add
    securetoken_double_check
    adduser_filevault
elif [[ "$secureTokenCheck" =~ "ENABLED" ]]; then
    securetoken_success
    adduser_filevault
else
    echo "Error with sysadminctl"
    /bin/launchctl "$L_METHOD" "$L_ID" "$jamfHelper" \
        -windowType "utility" \
        -title "Failure" \
        -description "Failure to run. Please contact $IT" \
        -button1 'OK' \
        -defaultButton 1 \
        -startlaunchd &>/dev/null &
fi

# Clear password variable.
unset loggedInUserPass
unset guiAdminPass

exit 0
