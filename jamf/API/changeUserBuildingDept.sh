#!/bin/bash

# Change mac assigned user and location through Self Service Policy
# jjourney 07/2016

## SETUP ##
# input $domain and $jamf info
# decrypt strings for user/pass --> https://github.com/jamfit/Encrypted-Script-Parameters
# adjust departments (if necessary), currently is set so that if a particular building is set, then do a manual call of departments 
#   for us, we only need a few departments (for printers)

###### Variables ######
# System
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamfBin="/usr/local/jamf/bin/jamf"
domain=""

# jamf
jamf=""

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '' '')
apiPass=$(DecryptString $5 '' '')

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

function 1ButtonInfoBox() {
osascript <<EOT
tell app "System Events"
with timeout of 86400 seconds
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end timeout
end tell
EOT
}

function 2ButtonInfoBox() {
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

# Departments
# If adding a Department, add it to DepartmentArray
# If there is a space between words, eg "Gandalf the White" it must be "Gandalf_the_White" 
# All underscores will be removed later
DepartmentArray=()
Array=()
for building in ${DepartmentArray[@]} 
do
    Array+=$"${building}\n"
done
Array=$(echo $Array |sed 's/..$//')

# Department, overwrites if another department is specified later.
apiDeptData="<computer><location><department/></location></computer>"

## Set up loop for username/password check
e=1
while [[ $e -ne 2 ]]
do
# Get computer name/check JSS connection
oldName="$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
    -H "Accept: application/xml" \
    | xpath //computer/general/name[1] \
    | sed -e 's/<name>//;s/<\/name>//' \
    )"
# if yes, continue
if [ -z "$oldName" ]; then
    error_full="$(2ButtonInfoBox \
        "There seems to be an issue connecting to jamf. Press OK to try again" \
        "Error" \
        "Cancel" \
        "OK")"
    if [[ "$error_full" =~ "OK" ]]; then
        continue
    fi
fi
e=2
done    
        
#### changing computer name ######
# Enter new computer name
newComputerName="$(simpleInput \
    "Please enter the new computer name:" \
    "New Name" \
    "Cancel" \
    "OK" \
    "$oldName")"
if [[ "$?" != 0 ]]; then
    exit 0
fi

# Make sure there is no space (" ") 
pattern=" |'"
while [[ -z "$newComputerName" || "$newComputerName" =~ $pattern ]]
    do
    newComputerName="$(simpleInput \
        "Please enter the new computer name:" \
        "New Name" \
        "Cancel" \
        "OK" \
        "$oldName")" 
done

newUserName="$(simpleInput \
    "Please enter the $domain of the primary user. You can cancel if this is not a DEP machine." \
    "User assignment" \
    "Cancel" \
    "OK")"
if [[ ! -z "$newUserName" ]]; then
    echo "updating username"
    userData="<computer><location><username>$newUserName</username></location></computer>"
    curl \
        -s \
        -f \
        -u $apiUser:$apiPass \
        -X PUT \
        -H "Content-Type: text/xml" \
        -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$userData" $jamf/JSSResource/computers/serialnumber/$serialNumber
fi

# set apiData
apiData="<computer><general><name>$newComputerName</name></general></computer>"

# Final PUT command, updating new Name
curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jamf/JSSResource/computers/serialnumber/$serialNumber
    
# Change variable
computerName="$newComputerName"
    
# Run policy to have it update
sudo jamf policy -trigger polForceName

# New Check
checkName="$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
    -H "Accept: application/xml" \
    | xpath //computer/general/name[1] \
    | sed -e 's/<name>//;s/<\/name>//' \
    )"

# Display newest Name
1ButtonInfoBox \
    "The new name is $checkName" \
    "Computer Name" \
    "OK"

## Get all Buildings
allBuildings=$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/buildings \
    -H "Accept: application/xml" \
    | xmllint --format - \
    | awk -F'>|<' '/<id>/,/<name>/{print $3}'\
    )

buildingArray=()
BuildingList=$(echo "$allBuildings" | awk 'NR % 2 == 0' | sed 's/^//g;s/$//g')
for building in $BuildingList
do
    buildingArray+=$"${building}\n"
done
buildingArray=$(echo $buildingArray |sed 's/..$//')

Building="$(listChoice \
    "Make a selection below:" \
    "Choose Building" \
    "Cancel" \
    "OK" \
    "$buildingArray")"
if [[ "$Building" =~ "false" ]]; then
    exit 0
    echo "user cancelled"
fi

# Fix underscores
    if [[ "$Building" =~ "_" ]]; then
        Building="$(echo $Building | sed -e 's/_/ /g')"
    fi

# If __, ask for departments
if [[ "$Building" =~ "" ]]; then
    Dept="$(listChoice \
        "Make a selection below. Underscores will be removed:" \
        "Choose Department" \
        "Cancel" \
        "OK" \
        "$Array")"
    if [[ "$Dept" =~ "false" ]]; then
        exit 0
        echo "user cancelled"
    fi
    
    # Fix underscores
    if [[ "$Dept" =~ "_" ]]; then
        Dept="$(echo $Dept | sed -e 's/_/ /g')"
    fi
    
    # Set new department variable
    apiDeptData="$(echo "<computer><location><department><name>$Dept</name></department></location></computer>")"
    # PUT command, updating department
    curl \
        -s \
        -f \
        -u $apiUser:$apiPass \
        -X PUT \
        -H "Content-Type: text/xml" \
        -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiDeptData" $jamf/JSSResource/computers/serialnumber/$serialNumber
fi

# Building data
apiBuildingData="$(echo "<computer><location><building><name>$Building</name></building></location></computer>")"

# PUT command, updating building
curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiBuildingData" $jamf/JSSResource/computers/serialnumber/$serialNumber

# New Check
checkBuilding="$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
    -H "Accept: application/xml" \
    | xpath //computer/location/building[1] \
    | sed -e 's/<building>//;s/<\/building>//' \
    )"

# Display newest Name
1ButtonInfoBox \
    "The new building name is $checkBuilding." \
    "Complete!" \
    "OK"

exit 0
