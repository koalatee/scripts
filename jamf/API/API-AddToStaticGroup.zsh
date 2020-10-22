#!/bin/zsh

# Add/Remove Machines to Static Groups
# jjourney 08/2016

## Updates
#  06/2018 - removed cocoa dialog, all applescript

###### Variables ######
# System
computerName="$(scutil --get ComputerName)"

# jamf url
jamf=""

# xpath on macOS 11 requires -e 
osversion=$(sw_vers -productVersion |cut -d . -f 1)
if [[ $osversion -eq "10" ]]; then
    xpathcode="xpath"
else
    xpathcode="xpath -e"
fi

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
with timeout of 2700 seconds
text returned of (display dialog "$1" default answer "$5" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function hiddenInput() {
osascript <<EOT
tell app "System Events" 
with timeout of 2700 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function OneButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
} 

function TwoButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
button returned of (display dialog "$1" buttons {"$3", "$4"} default button 2 with title "$2")
end timeout
end tell
EOT
}

function listChoice() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
choose from list every paragraph of "$5" with title "$2" with prompt "$1" OK button name "$4" cancel button name "$3"
end timeout
end tell
EOT
}

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '03a49bc11d67608c' '11b9ec057f88069ab643816b')
apiPass=$(DecryptString $5 '9183a4a510332d53' 'a41775e19fc4f189f2e206dd')

##### select computer to add #####
choice=1
until [ $choice -eq "2" ]; do
    
    ## prompt for computer name ## 
    computerAdd="$(simpleInput \
        "Please enter the name of the machine you want to add. Current machine name is listed. If you need to remove, go through jamf." \
        "Computer Name" \
        "Cancel" \
        "OK" \
        "$computerName" \
        )"
    if [[ "$?" != 0 ]]; then
        exit 0
    fi

    ## check to make sure that the computer is in JSS ##
    computerAdd_NameCheck="$(curl \
            -s \
            -f \
            -u $apiUser:$apiPass \
            -X GET $jamf/JSSResource/computers/name/$computerAdd \
            -H "Accept: application/xml" \
            | $(echo $xpathcode) /computer/general/name \
            | sed -e 's/<name>//;s/<\/name>//' \
            )"
    # if blank, loop
    if [ -z "$computerAdd_NameCheck" ]; then
        OneButtonInfoBox \
            "Either the machine name does not exist in jamf, or there is another issue. Please try again." \
            "Error" \
            "OK" 
        exit 1
    # if not blank, end
    else
        choice=2
    fi
done

# get S/N of machine name
serialNumber="$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computers/name/$computerAdd \
    -H "Accept: application/xml" \
    | $(echo $xpathcode) /computer/general/serial_number \
    | sed -e 's/<serial_number>//;s/<\/serial_number>//' \
    )"

##### get a list of all static groups #####
## Get all groups
allGroups=$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computergroups \
    -H "Accept: application/xml" \
    | xmllint --format - \
    )

# make it alphabetical and only ones that are static
index=0 # start at the bottom
staticGroupArray=() # start blank
staticGroupArrayFinal=() # again, start blank
size=$(echo $allGroups \
    |$(echo $xpathcode) //computer_groups/size \
    |sed 's/<[^>]*>//g' )

while [ $index -lt ${size} ]
do
    index=$[$index+1]
    groupinfo_issmart=$(echo $allGroups \
        | $(echo $xpathcode) '/computer_groups/computer_group['$index']/is_smart' )
    if [[ $groupinfo_issmart =~ "false" ]]; then
        group_info_name=$(echo $allGroups \
            | $(echo $xpathcode) '/computer_groups/computer_group['$index']/name' \
            |sed 's/<[^>]*>//g')
        staticGroupArray+=("$group_info_name")
    fi
done

# make it alphabetical
IFS=$'\n' sorted=($(sort <<< "${staticGroupArray[*]}"))
unset IFS

# this... works?
staticGroupArrayFinal=$(for item in "${sorted[@]}"
do
    echo $item
done)
    
staticGroupChoice="$(listChoice \
    "Which group would you like to add $computerAdd to?" \
    "Choose Static Group" \
    "Cancel" \
    "OK" \
    "$staticGroupArrayFinal" \
    )"

# Get static group ID so you can list machines in group
groupID="$(echo $allGroups \
    | $(echo $xpathcode) '/computer_groups/computer_group[name = '$staticGroupChoice']/id' \
    | sed -e 's/<id>//;s/<\/id>//' \
    )"

## add new machine to the array ##
apiData="<computer_group><computer_additions><computer><serial_number>$serialNumber</serial_number></computer></computer_additions></computer_group>"

curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jamf/JSSResource/computergroups/id/$groupID
    
## Success ##    
OneButtonInfoBox \
    "Computer $computerAdd with serial number $serialNumber has been added to $staticGroupChoice" \
    "Computer Added" \
    "OK"
    
exit 0
