#!/bin/zsh

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '03a49bc11d67608c' '11b9ec057f88069ab643816b')
apiPass=$(DecryptString $5 '9183a4a510332d53' 'a41775e19fc4f189f2e206dd')

# API URL
jamfURL="https://rtsmacs.asu.edu:8443"

ad_computer_name=$(dsconfigad -show | grep "Computer Account" | awk '{print $4}')
ad_computer_ou=$(dscl /Search read /Computers/$ad_computer_name | \
    grep dsAttrTypeNative:distinguishedName | \
    cut -d, -f2- | \
    awk -F, '{print $1}' | \
    awk -F= '{print $2}' )

echo "Computer $ad_computer_name is in OU $ad_computer_ou" 
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>AD_OU</name><value>$ad_computer_ou</value></extension_attribute></extension_attributes></computer>"

# Update the LAPS Extention Attribute
UpdateAPI (){
/usr/bin/curl \
    -s \
    -u ${apiUser}:${apiPass} \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "${xmlString}" "${jamfURL}/JSSResource/computers/udid/$udid"
}

UpdateAPI
