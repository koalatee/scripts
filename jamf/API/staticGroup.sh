#!/bin/bash

# Add/Remove Machines to Static Groups
# jjourney 08/2016

###### Variables ######
# System
CocoaD="/Library/$company/CD/CocoaDialog.app/Contents/MacOS/CocoaDialog"
computerName="$(scutil --get ComputerName)"
#serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# JSS
jss="https://your.jss.here:8443"


###### Exit if CD not found ######
## Will try and download policy with trigger listed
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
## Get Username
username_Full="$($CocoaD \
    standard-inputbox \
    --title "$AD ID" \
    --informative-text "Please enter your $AD ID." \
    --empty-text "Please type in your $AD before clicking OK." \
    --button1 "OK" \
    --button2 "Cancel" \
    --float \
    --string-output )"
if [[ "$username_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
username=${username_Full:3}

## Get Password
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
password="${password_Full:3}"

##### select computer to add #####
choice=1
until [ $choice -eq "2" ]; do
    
    ## prompt for computer name ## 
    computerAdd_Full="$($CocoaD \
        standard-inputbox \
        --title "Computer Name" \
        --informative-text "Please enter the name of the machine you want to add. Current machine name is listed. If you need to remove, go through JSS" \
        --text "$computerName" \
        --empty-text "Please type in a computer name before clicking OK." \
        --button1 "OK" \
        --button2 "Cancel" \
        --float \
        --string-output )"
    if [[ "$computerAdd_Full" =~ "Cancel" ]]; then
        exit 0
        echo "user cancelled"
    fi
    computerAdd=${computerAdd_Full:3}

    ## check to make sure that the computer is in JSS ##
    computerAdd_NameCheck="$(curl \
            -s \
            -v \
            -u $username:$password \
            -X GET $jss/JSSResource/computers/name/$computerAdd \
            -H "Accept: application/xml" \
            | xpath //computer/general/name[1] \
            | sed -e 's/<name>//;s/<\/name>//' \
            )"
    # if blank, loop
    if [ -z "$computerAdd_NameCheck" ]; then
        $CocoaD ok-msgbox \
            --title "Error" \
            --text "Error" \
            --informative-text "Either the machine name does not exist in JSS, or there is an authentication issue. Please cancel or try again." \
            --float 
    # if not blank, end
    else
        choice=2
    fi
done

serialNumber="$(curl \
    -s \
    -v \
    -u $username:$password \
    -X GET $jss/JSSResource/computers/name/$computerAdd \
    -H "Accept: application/xml" \
    | xpath //computer/general/serial_number[1] \
    | sed -e 's/<serial_number>//;s/<\/serial_number>//' \
    )"

##### get a list of all static groups #####
## Get all groups
allGroups="$(curl \
    -s \
    -v \
    -u $username:$password \
    -X GET $jss/JSSResource/computergroups \
    -H "Accept: application/xml" \
    )"
    
## Pull out all static groups | parse out <is_smart>false</is_smart>
staticGroupList="$(echo $allGroups \
    | xpath "/computer_groups/computer_group[is_smart = 'false']/name" \
    | sed -e 's/ /_/g' \
    | sed -e 's/<name>/ /g;s/<\/name>//g' \
    )"

##### list static group that you want to add machine to #####
addStaticGroup="$($CocoaD \
    standard-dropdown \
    --string-output \
    --title "Choose Static Group" \
    --text "Which group would you like to add it to? Underscores will be removed:" \
    --items $staticGroupList \
    --float \
    )" 
staticGroupChoice=${addStaticGroup:2}

# GET requires encoded (space becomes %20)
staticGroup2="$(echo $staticGroupChoice | sed -e 's/_/ /g')"
# Get static group ID so you can list machines in group
groupID="$(echo $allGroups \
    | xpath "/computer_groups/computer_group[name = '$staticGroup2']/id" \
    | sed -e 's/<id>//;s/<\/id>//' \
    )"

## add new machine to the array ##
apiData="<computer_group><computer_additions><computer><serial_number>$serialNumber</serial_number></computer></computer_additions></computer_group>"

curl \
    -s \
    -v \
    -u \
    $username:"$password" \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jss/JSSResource/computergroups/id/$groupID
    
## Success ##    
$CocoaD \
    ok-msgbox \
    --title "Computer Added" \
    --text "$staticGroup2" \
    --informative-text "Computer $computerAdd with serial number $serialNumber has been added to $staticGroup2." \
    --float \
    --no-cancel

exit 0
