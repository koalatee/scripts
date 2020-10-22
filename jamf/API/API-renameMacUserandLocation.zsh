#!/bin/zsh

# Change mac name, assigned user, and location through Self Service Policy
# jjourney 07/2016

## Updates::
# 10/2016 added a loop to check credentials
# 11/2017 added assigned username change
# 06/2018 removed cocoa dialog, all applescript

###### Variables ######
# System
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamfBin="/usr/local/jamf/bin/jamf"

# jamf urk
jamf=""
domainID="" # <--- this will pop up when you are selecting a userID to assign the mac to

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

function simpleInputNoCancel() {
osascript <<EOT
tell app "System Events"
with timeout of 2700 seconds
text returned of (display dialog "$1" default answer "$4" buttons {"$3"} default button 1 with title "$2")
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

function hiddenInputNoCancel() {
osascript <<EOT
tell app "System Events" 
with timeout of 2700 seconds
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3"} default button 1 with title "$2")
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
apiUser=$(DecryptString $4 '' '')
apiPass=$(DecryptString $5 '' '')

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
    | $(echo $xpathcode) /computer/general/name \
    | sed -e 's/<name>//;s/<\/name>//' \
    )"
# if yes, continue
if [ -z "$oldName" ]; then
    error_full="$(TwoButtonInfoBox \
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

# get ASURITE of primary user
newUserName="$(simpleInput \
    "Please enter the $domainID of the primary user. You can cancel if this is not a DEP machine." \
    "User assignment" \
    "Cancel" \
    "OK")"
    
if [[ "$?" != 0 ]]; then
    echo "user cancelled"
else
	# make sure user actually exists
	userLDAP=$(curl \
    	-s \
	    -f \
    	-u $apiUser:$apiPass \
	    -X GET $jamf/JSSResource/ldapservers/id/1/user/$newUserName \
    	-H "Accept: application/xml" )

	# Make sure there is no space (" ") 
	pattern=" |'"
	while [[ -z "$newUserName" || "$newUserName" =~ $pattern || ! "$userLDAP" =~ "realname" ]]
    	do
	    newUserName="$(simpleInput \
    	    "$domainID incorrect or does not exist. Please enter the $domainID of the primary user:" \
        	"New Name" \
			"Cancel" \
			"OK")" 
        if [[ "$?" != 0 ]]; then
        	break
            echo "User cancelled"
        fi
      
    	userLDAP=$(curl \
        	-s \
	        -f \
    	    -u $apiUser:$apiPass \
        	-X GET $jamf/JSSResource/ldapservers/id/1/user/$newUserName \
	        -H "Accept: application/xml" )
	done
fi

if [[ ! -z "$newUserName" ]]; then
    # get all dat info
    userLDAP=$(curl \
        -s \
        -f \
        -u $apiUser:$apiPass \
        -X GET $jamf/JSSResource/ldapservers/id/1/user/$newUserName \
        -H "Accept: application/xml" )
    realName=$(echo $userLDAP \
        | $(echo $xpathcode) /ldap_users/ldap_user/realname \
        | sed -e 's/<realname>//;s/<\/realname>//')
    emailAddress=$(echo $userLDAP \
        | $(echo $xpathcode) /ldap_users/ldap_user/email_address \
        | sed -e 's/<email_address>//;s/<\/email_address>//')
    phoneNumber=$(echo $userLDAP \
        | $(echo $xpathcode) /ldap_users/ldap_user/phone \
        | sed -e 's/<phone>//;s/<\/phone>//')
    position=$(echo $userLDAP \
        | $(echo $xpathcode) /ldap_users/ldap_user/position \
        | sed -e 's/<position>//;s/<\/position>//')

    echo "updating username"
    userData="<computer><location><username>$newUserName</username><realname>$realName</realname><real_name>$realName</real_name><email_address>$emailAddress</email_address><phone>$phoneNumber</phone><phone_number>$phoneNumber</phone_number><position>$position</position></location></computer>"
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
    | $(echo $xpathcode) /computer/general/name \
    | sed -e 's/<name>//;s/<\/name>//' \
    )"

# Display newest Name
OneButtonInfoBox \
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
    )

# make it alphabetical
index=0 # start at the bottom
buildingArray=() # start blank
buildingArrayFinal=() # again, start blank
size=$(echo $allBuildings \
    |$(echo $xpathcode) //buildings/size \
    |sed 's/<[^>]*>//g' \
    )
# make an array
while [ $index -lt ${size} ] 
do 
    index=$[$index+1]
    building=$(echo $allBuildings \
        | $(echo $xpathcode) '//buildings/building['$index']/name' \
        |sed 's/<[^>]*>//g')
    buildingArray+=("$building")
done

# make it alphabetical
IFS=$'\n' sorted=($(sort <<< "${buildingArray[*]}"))
unset IFS

# this... works?
buildingArrayFinal=$(for item in "${sorted[@]}"
do
    echo $item
done)

# Set building
Building="$(listChoice \
    "Make a selection below:" \
    "Choose Building" \
    "Cancel" \
    "OK" \
    "$buildingArrayFinal")"
if [[ "$Building" =~ "false" ]]; then
    exit 0
    echo "user cancelled"
fi

# Ask for new room info
oldRoom="$(curl \
    -s \
    -f \
    -u $apiUser:$apiPass \
    -X GET $jamf/JSSResource/computers/serialnumber/$serialNumber \
    -H "Accept: application/xml" \
    | $(echo $xpathcode) /computer/location/room \
    | sed -e 's/<room>//;s/<\/room>//' \
    )"

if [[ "$oldRoom" = "<room />" ]]; then
    roomMessage="$BlankRoomMessage"
    oldRoom=""
fi
newRoom="$(simpleInput \
    "$roomMessage" \
    "Room Info" \
    "Cancel" \
    "OK" \
    "$oldRoom" )"
# confirmation of computer name
newRoom="$(simpleInput \
    "Verify that this info is correct:" \
    "Room Info Verification" \
    "Cancel" \
    "OK" \
    "$newRoom")"    

# Building data 
## ADDED ROOM INFO
apiBuildingData="$(echo "<computer><location><building><name>$Building</name></building><room><name>$newRoom</name></room></location></computer>")"

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
    | $(echo $xpathcode) /computer/location/building \
    | sed -e 's/<building>//;s/<\/building>//' \
    )"

# Display newest Name
OneButtonInfoBox \
    "The new building name is $checkBuilding." \
    "Complete!" \
    "OK"

exit 0
