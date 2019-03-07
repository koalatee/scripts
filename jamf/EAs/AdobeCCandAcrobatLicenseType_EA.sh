#!/bin/sh

###### jjourney 01/2017 ######
# Checks Adobe CC license type
# Update 3/2019 
# Checks Acrobat as well

# This should check your CC install (via swidtag) and Acrobat install to see what license is installed (if any)
# Writes to extension attributes (because do you need this to run every recon? probably not)
# See setup for what parameters to pass and what policies to setup

### Script Setup:
# Enter appropriate parameter changes
# - 4 is encrypted user string
# - 5 is encrypted pass string
# - 6 is CC swidtag location (shouldn't change?)
# - 7 is where the AdobeExpiryTool is located locally on the machine (see note below)
# - 8 is trigger to download if not found (or you can include it with this policy)
# - 9 is Creative Cloud License EA ID
# - 10 is Acrobat Pro License EA ID
### Policy Setup:
# Setup a jamf policy with this script and the correct parameters
# Setup another jamf policy with the trigger to install the AcrobatExpiryTool
### jamf setup:
# Setup 2 computer extension attributes with string data type and text field entry
# ID goes in $9 and $10

# API URL
apiURL="https://your.jamf.here:8443"

# Adobe SWID file
# Should be:
# /Library/Application Support/regid.1986-12.com.adobe/regid.1986-12.com.adobe_V7{}CreativeCloudEnt-1.0-Mac-GM-MUL.swidtag
adobeCCFile="${6}"
# Path to the Acrobat Tool https://helpx.adobe.com/enterprise/kb/volume-license-expiration-check.html
acrobatTool="${7}"
# some trigger to download the tool if not found
DownloadAcrobatTool="${8}"
# CC License EA ID
CCLicenseEA="${9}"
# Acrobat License EA ID
AcrobatLicenseEA="${10}"

## These go in your EA
AcrobatNamedUserInstall="Acrobat Pro Named-User license installed"
AcrobatSerialInstall="Acrobat Pro Serial license installed"
AcrobatError="Unknown Issue with License Tool"
AcrobatNotInstalled="Acrobat Pro Not Installed"
CCNotInstalled="Creative Cloud not Installed"
CCUninstalled="Creative Cloud uninstalled"
CCError="Creative Cloud error"

# Function to decrypt the string
# https://github.com/jamf/Encrypted-Script-Parameters
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '$saltgoeshere' '$passphrasegoeshere')
apiPass=$(DecryptString $5 '$saltgoeshere' '$passphrasegoeshere')

################################
# Get the username of the logged in user
loggedInUser=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )

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
        resultACR="$AcrobatNamedUserInstall"
    elif [[ "$SerialCheck" =~ "EncryptedSerial" ]]; then
        resultACR="$AcrobatSerialInstall"
    else 
        resultACR="$AcrobatError"
    fi
else
    resultACR="$AcrobatNotInstalled"
fi

## See if file is actually present, if it is, result is echod. Else, result shows TYPE:loggedInUser
if [[ ! -f "$adobeCCFile" ]]; then
    resultCC="$CCNotInstalled"
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
        resultCC="$CCUninstalled"
    else
        resultCC="$CCError"
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
/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"
}

UpdateAPI

exit 0
