#!/bin/bash

# Change mac location through Self Service Policy
# jjourney 07/2016

# set your jss
# set your $AD


###### Variables ######
# System
CocoaD="/Library/$company/CD/CocoaDialog.app/Contents/MacOS/CocoaDialog"
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"

# JSS
AD=""
jss="https://your.jss.here:8443"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Department, overwrites if another department is specified later.
apiDeptData="<computer><location><department/></location></computer>"

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
    --string-output )"
if [[ "$password_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
password=${password_Full:3}

## Get all Buildings
allBuildings="$(curl \
    -s \
    -u $username:$password \
    -X GET $jss/JSSResource/buildings \
    -H "Accept: application/xml" \
    )"
    
BuildingList="$(echo $allBuildings \
    | xpath "/buildings/building/name" \
    |sed -e 's/<name>//g;s/<\/name>/ /g' \
    )"

# Enter user's building information
userBuilding="$($CocoaD \
    standard-dropdown \
    --string-output \
    --title "Choose Building" \
    --text "Make a selection below:" \
    --items $BuildingList \
    --float \
    )"
if [[ "$userBuilding" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
Building=${userBuilding:3}

# Fix underscores
    if [[ "$Building" =~ "_" ]]; then
        Building="$(echo $Building | sed -e 's/_/ /g')"
    fi

# Building data
apiBuildingData="$(echo "<computer><location><building><name>$Building</name></building></location></computer>")"

# PUT command, updating building
curl \
    -s \
    -u $username:$password \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiBuildingData" $jss/JSSResource/computers/serialnumber/$serialNumber
# PUT command, updating location
curl \
    -s \
    -u $username:$password \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiDeptData" $jss/JSSResource/computers/serialnumber/$serialNumber

# New Check
checkBuilding="$(curl \
    -s \
    -u $username:$password \
    -X GET $jss/JSSResource/computers/serialnumber/$serialNumber \
    -H "Accept: application/xml" \
    | xpath //computer/location/building[1] \
    | sed -e 's/<building>//;s/<\/building>//' \
    )"

# Display newest Name
displayNewName="$($CocoaD \
    ok-msgbox \
    --title "Complete" \
    --text "New Building Name" \
    --informative-text "The new building name is $checkBuilding" \
    --float )"

exit 0
