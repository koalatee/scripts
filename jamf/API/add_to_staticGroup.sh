#!/bin/bash

##### Variables #####
# setup
# upload script to jamf
# set parameters:
# 4 = apiUser Encrypted String
# 5 = apiPass Encrypted String
# 6 = static group ID# 
# attach to a policy and fill in respective values

jamfURL="your.jamf.here:8443"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
groupID="${6}" 

## Function for api account string decryption
## https://github.com/jamfit/Encrypted-Script-Parameters
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}
## Decrypt username + password
apiUser=$(DecryptString $4 'apiUser salt here' 'apiUser passphrase here')
apiPass=$(DecryptString $5 'apiPass salt here' 'apiPass passphrase here')

# Add to static group
apiData="<computer_group><computer_additions><computer><serial_number>$serialNumber</serial_number></computer></computer_additions></computer_group>"
# curl command
curl \
    -s \
    -f \
    -u ${apiUser}:${apiPass} \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$apiData" $jamfURL/JSSResource/computergroups/id/$groupID
    
exit 0
