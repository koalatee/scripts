#!/bin/zsh

###### jjourney 01/2017 ######
# Checks Adobe license type

# Update 3/2019 
# Checks Acrobat as well?

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '' '')
apiPass=$(DecryptString $5 '' '')

# jamf URL
apiURL=""

# Adobe SWID file
# /Library/Application Support/regid.1986-12.com.adobe/regid.1986-12.com.adobe_V7{}CreativeCloudEnt-1.0-Mac-GM-MUL.swidtag
adobeCCFile="${6}"
# /path/to/AdobeExpiryCheck
acrobatTool="${7}"
# some trigger
DownloadAcrobatTool="${8}"
# CC License EA
CCLicenseEA="${9}"
# Acrobat License EA
AcrobatLicenseEA="${10}"

################################
# Get the username of the logged in user
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}     ' )

# Make sure someone is logged in
if [[ -z "$loggedInUser" ]]; then
    echo "No one logged in, will run again next week."
    exit 1
fi

## Check Acrobat Pro
if [[ ! -e "$acrobatTool" ]]; then
    jamf policy -event $DownloadAcrobatTool
fi

SerialCheck=$("$acrobatTool" 2> /dev/null)
if [[ -e "/Applications/Adobe Acrobat DC"  ]] || [[ -e "/Applications/Adobe Acrobat 2015" ]] || [[ -e "/Applications/Adobe Acrobat XI Pro" ]] || [[ -e "/Applications/Adobe Acrobat X Pro" ]] || [[ -e "/Applications/Adobe Acrobat 9 Pro" ]] || [[ -e "/Applications/Adobe Acrobat 8 Professional" ]]; then
    if [[ "$SerialCheck" =~ "No expiring/expired serial number" ]]; then
        resultACR="Acrobat Pro Named-User license installed"
    elif [[ "$SerialCheck" =~ "EncryptedSerial" ]]; then
        resultACR="Acrobat Pro Serial license installed"
    else 
        resultACR="Unknown Issue with License Tool"
    fi
else
    resultACR="Acrobat Pro Not Installed"
fi

## See if file is actually present, if it is, result is echod. Else, result shows TYPE:loggedInUser
if [[ ! -f "$adobeCCFile" ]]; then
    resultCC="ASU Creative Cloud Not Installed"
else
    ## Find channel type
    # VOLUME == Full installer      
    # SUBSCRIPTION == named-user        
    # UNKNOWN == uninstalled or other error
    channel_type=$(xmllint --xpath "//*[local-name()='license_linkage']/*[local-name()='channel_type']" "$adobeCCFile" \
        | sed -e 's/<swid:channel_type>//;s/<\/swid:channel_type>//')
    if [[ "$channel_type" =~ "VOLUME" || "$channel_type" =~ "SUBSCRIPTION" ]]; then
        resultCC=$channel_type:$loggedInUser
    elif [[ "$channel_type" =~ "UNKNOWN" ]]; then
        resultCC="ASU Creative Cloud uninstalled"
    else
        resultCC="ASU Creative Cloud error"
    fi
fi  

echo "Acrobat: $resultACR"
echo "CC: $resultCC"

################################
## API upload values
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><id>$CCLicenseEA</id><value>$resultCC</value></extension_attribute><extension_attribute><id>$AcrobatLicenseEA</id><value>$resultACR</value></extension_attribute></extension_attributes></computer>"

# Update the Adobe CC Extention Attribute
UpdateAPI (){
/usr/bin/curl \
  -s \
  -u ${apiUser}:${apiPass} \
  -X PUT \
  -H "Content-Type: text/xml" \
  -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"
}

UpdateAPI

exit 0
