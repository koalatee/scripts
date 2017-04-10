#!/bin/sh

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '' '')
apiPass=$(DecryptString $5 '' '')

# API URL
apiURL="https://your.jss.here:8443"

ad_computer_name=$(dsconfigad -show | grep "Computer Account" | awk '{print $4}')
ad_computer_ou=$(dscl /Search read /Computers/$ad_computer_name | \
grep -A 1 dsAttrTypeNative:distinguishedName | \
cut -d, -f2- | sed -n 's/OU\=//gp' | \
sed -n 's/\(.*\),DC\=/\1./gp' | \
sed -n 's/DC\=//gp' | \
awk -F, '{
N = NF
while ( N > 1 )
{
printf "%s/",$N
N--
}

printf "%s",$1
}')
echo "Computer $ad_computer_name is in OU $ad_computer_ou" 
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')
xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>AD_OU</name><value>$ad_computer_ou</value></extension_attribute></extension_attributes></computer>"

# Identify the location of the jamf binary for the jamf_binary variable.
CheckBinary (){
# Identify location of jamf binary.
jamf_binary=$(/usr/bin/which jamf)

if [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ ! -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/sbin/jamf"
elif [[ "$jamf_binary" == "" ]] && [[ ! -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/local/bin/jamf"
elif [[ "$jamf_binary" == "" ]] && [[ -e "/usr/sbin/jamf" ]] && [[ -e "/usr/local/bin/jamf" ]]; then
jamf_binary="/usr/local/bin/jamf"
fi
}

# Update the LAPS Extention Attribute
UpdateAPI (){
/usr/bin/curl -s -u ${apiUser}:${apiPass} -X PUT -H "Content-Type: text/xml" -d "${xmlString}" "${apiURL}/JSSResource/computers/udid/$udid"
}

CheckBinary
UpdateAPI

echo "AD OU Finished."

exit 0
