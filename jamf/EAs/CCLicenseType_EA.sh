#!/bin/sh

###### jjourney 01/2017 ######
# Checks Adobe license type
# Should output one of the following:
# NONE
# SUBSCRIPTION:$loggedInUser
# VOLUME:$loggedInUser

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '' '')
apiPass=$(DecryptString $5 '' '')

# API URL
apiURL="https://your.jss.com:8443"

# Adobe SWID file
adobeFile="/Library/Application Support/regid.1986-12.com.adobe/regid.1986-12.com.adobe_V7{}CreativeCloudEnt-1.0-Mac-GM-MUL.swidtag"

################################
# Get the username of the logged in user
loggedInUser=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')

# Make sure someone is logged in
if [[ -z "$loggedInUser" ]]; then
    echo "No one logged in, will run again next week."
    exit 1
fi

## See if file is actually present, if it is, result is echod. Else, result shows TYPE:loggedInUser
if [[ ! -f "$adobeFile" ]]; then
    result="Creative Cloud Not Installed"
else
    ## Find channel type
    # VOLUME == Full installer      
    # SUBSCRIPTION == named-user        
    # UNKNOWN == uninstalled or other error
    channel_type=$(xmllint --xpath "//*[local-name()='license_linkage']/*[local-name()='channel_type']" "$adobeFile" \
        | sed -e 's/<swid:channel_type>//;s/<\/swid:channel_type>//')
    if [[ "$channel_type" =~ "VOLUME" || "$channel_type" =~ "SUBSCRIPTION" ]]; then
        result=$channel_type:$loggedInUser
        echo $result
    elif [[ "$channel_type" =~ "UNKNOWN" ]]; then
        result="Creative Cloud uninstalled"
        echo $result
    else
        result="Creative Cloud error"
        echo $result
    fi
fi  

################################
## API upload values
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>AdobeCCLicense:Username</name><value>$result</value></extension_attribute></extension_attributes></computer>"

# Update the Adobe CC Extention Attribute
UpdateAPI (){
/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"
}

UpdateAPI

exit 0
