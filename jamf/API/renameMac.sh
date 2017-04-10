#!/bin/bash

# Rename Mac through Self Service Policy
# jjourney 07/2016

###### Variables ######
# System
CocoaD="/Library/$company/CD/CocoaDialog.app/Contents/MacOS/CocoaDialog"
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# JSS
jss="https://your.jss.here:8443"


###### Exit if CD not found ######
# Will try and download policy with trigger listed
trigger="polCocoaDialog"
i=1
while [[ ! -f "$CocoaD" ]] && [[ $i -ne 4 ]]
do
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "Error" \
        -description "Dependencies not found with install. Try number $i to download dependencies..." \
        -lockHUD \
        -timeout 10 \
        -countdown
    sudo jamf policy -trigger "$trigger"
    i=$(( $i + 1 ))
done

if [[ $i -eq 4 ]]; then
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "Error" \
        -description "Dependencies not able to be downloaded. Please contact your administrator" \
        -button1 "OK" \
        -lockHUD
    exit 1
fi


###### User info ######
# Get Username
username_Full="$($CocoaD \
    standard-inputbox \
    --title "$AD ID" \
    --informative-text "Please enter your $AD ID." \
    --empty-text "Please type in your $AD before clicking OK." \
    --button1 "OK" \
    --button2 "Cancel" \
    --float \
    --string-output \
    )"
if [[ "$username_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
username=${username_Full:3}

# Get Password
password_Full="$($CocoaD \
    secure-inputbox \
    --title "$AD Password" \
    --informative-text "Please enter your $AD Password" \
    --empty-text "Please type in your $AD Password before clicking OK." \
    --button1 "OK" \
    --button2 "Cancel" \
    --float \
    --string-output \
    )"
if [[ "$password_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
password="${password_Full:3}"


#### changing computer name ######
# ask if user wants to change it
computerName_prompt="$($CocoaD \
    yesno-msgbox \
    --title "Computer Name" \
    --text "$computerName" \
    --informative-text "The current name is $computerName. Would you like to change it?" \
    --float \
    --no-cancel \
    )"  

# Prompts if the user says yes
if [ "$computerName_prompt" -eq 1 ]; then
    oldName="$(curl \
        -s \
        -v \
        -u $username:"$password" \
        -X GET $jss/JSSResource/computers/serialnumber/$serialNumber \
        -H "Accept: application/xml" \
        | xpath //computer/general/name[1] \
        | sed -e 's/<name>//;s/<\/name>//' \
        )"
    # if yes, continue
    if [ -z "$oldName" ]; then
        $CocoaD \
            ok-msgbox \
            --title "Error Connecting to JSS" \
            --text "Error" \
            --informative-text "There seems to be an issue connecting to JSS. Please try again." \
            --float 
        exit 1
    else
        # Enter new computer name
        newComputerName="$($CocoaD \
        standard-inputbox \
        --title "New Name" \
        --informative-text "Please enter the new Name:" \
        --text "$oldName" \
        --button1 "OK" \
        --button2 "Cancel" \
        --float \
        --value-required \
        --string-output \
        )"
        if [[ "$newComputerName" =~ "Cancel" ]]; then
            exit 0
            echo "user cancelled"
        fi
        newComputerName=${newComputerName:3}
        # Make sure there is no space (" ") 
        pattern=" |'"
        while [[ -z "$newComputerName" || "$newComputerName" =~ $pattern ]]
            do
            newComputerName="$($CocoaD \
            standard-inputbox \
            --title "New Name" \
            --informative-text "Cannot contain a space or be blank, please enter the new name:" \
            --text "$oldName" \
            --empty-text "$oldName" \
            --button1 "OK" \
            --button2 "Cancel" \
            --float \
            --value-required \
            --string-output \
            )"
            if [[ "$newComputerName" =~ "Cancel" ]]; then
                exit 0
                echo "user cancelled"
            fi  
            newComputerName=${newComputerName:3}
        done

        # set apiData
        apiData="<computer><general><name>$newComputerName</name></general></computer>"

        # Final PUT command, updating new Name
        curl \
            -s \
            -v \
            -u \
            $username:"$password" \
            -X PUT \
            -H "Content-Type: text/xml" \
            -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jss/JSSResource/computers/serialnumber/$serialNumber
    
        # Change variable
        computerName="$newComputerName"
    
        # Run policy to have it update
        sudo jamf policy -trigger polForceName

        # New Check
        checkName="$(curl \
            -s \
            -v \
            -u $username:"$password" \
            -X GET $jss/JSSResource/computers/serialnumber/$serialNumber \
            -H "Accept: application/xml" \
            | xpath //computer/general/name[1] \
            | sed -e 's/<name>//;s/<\/name>//' \
            )"

        # Display newest Name
        $CocoaD \
            ok-msgbox \
            --title "Computer Name" \
            --text "$checkName" \
            --informative-text "The new name is $checkName." \
            --float \
            --no-cancel
    fi
fi

exit 0
