#!/bin/zsh

# More Accurate (than jamf) FV2 reporting 
# Write to EA for smart group reporting

## 10/2020 jjourney
# moved to zsh
# compatibility with macOS 11

### 
#           Taken from rtrouton (as always)
#           https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/check_apfs_encryption/check_apfs_encryption.sh
#           https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/Casper_Extension_Attributes/filevault_2_encryption_check/filevault_2_encryption_check_extension_attribute.sh
#
#           Modifications:
#               - this doesn't run every recon like a normal EA but runs on a schedule/on demand
#               - this adds the apiUser/apiPass, jamf, DecryptString, and API PUT at the end
#
###

# Function to decrypt the string
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Decrypt password
apiUser=$(DecryptString $4 '03a49bc11d67608c' '11b9ec057f88069ab643816b')
apiPass=$(DecryptString $5 '9183a4a510332d53' 'a41775e19fc4f189f2e206dd')

# API URL
jamfURL=""

# name of the EA 
ea_name=""

# hardware info for API
udid=$(/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/awk '/Hardware UUID:/ { print $3 }')

## messages
# If encrypted, the following message is 
# displayed without quotes:
# "FileVault is On."
#
# If encrypting, the following message is 
# displayed without quotes:
# "Encryption in progress:"
#
# If decrypting, the following message is 
# displayed without quotes:
# "Decryption in progress:"
#
# If not encrypted, the following message is 
# displayed without quotes:
# "FileVault is Off."
FVON="Filevault is On."
FVOFF="Filevault is Off."
FVPROGRESS="Encryption in progress:"
FVDEGRESS="Decryption in progress:"
FVDECRYPTED="Filevault is Off."
FVNA="Filevault unavailable"
FVVM="No CoreStorage, probably VM"

ENCRYPTSTATUS="/private/tmp/encrypt_status.txt"
ENCRYPTDIRECTION="/private/tmp/encrypt_direction.txt"

# OS info
osvers_major=$(sw_vers -productVersion | awk -F. '{print $1}')
osvers_minor=$(sw_vers -productVersion | awk -F. '{print $2}')

# If the Mac is running 10.7 or higher, but the boot volume
# is not a CoreStorage volume, the following message is 
# displayed without quotes:
#
# "FileVault 2 Encryption Not Enabled"
    
# If the Mac is running 10.7 or higher and the boot volume
# is a CoreStorage volume, the script then checks to see if 
# the machine is encrypted, encrypting, or decrypting.
# 
# If encrypted, the following message is 
# displayed without quotes:
# "FileVault 2 Encryption Complete"
#
# If encrypting, the following message is 
# displayed without quotes:
# "FileVault 2 Encryption Proceeding."
# How much has been encrypted of of the total
# amount of space is also displayed. If the
# amount of encryption is for some reason not
# known, the following message is 
# displayed without quotes:
# "FileVault 2 Encryption Status Unknown. Please check."
#
# If decrypting, the following message is 
# displayed without quotes:
# "FileVault 2 Decryption Proceeding"
# How much has been decrypted of of the total
# amount of space is also displayed
#
# If fully decrypted, the following message is 
# displayed without quotes:
# "FileVault 2 Decryption Complete"

boot_filesystem_check=$(/usr/sbin/diskutil info / | awk '/Type \(Bundle\)/ {print $3}')
corestorage=$(diskutil cs info / 2>&1)

# Get the Logical Volume UUID (aka "UUID" in diskutil cs info)
# for the boot drive's CoreStorage volume.
    
LV_UUID=$(diskutil cs info / | awk '/UUID/ {print $2;exit}')
    
# Get the Logical Volume Family UUID (aka "Parent LVF UUID" in diskutil cs info)
# for the boot drive's CoreStorage volume.
    
LV_FAMILY_UUID=$(diskutil cs info / | awk '/Parent LVF UUID/ {print $4;exit}')
    
CONTEXT=$(diskutil cs list $LV_FAMILY_UUID | awk '/Encryption Context/ {print $3;exit}')
    
if [[ ${osvers_major} -eq 10 ]] && [[ ${osvers_minor} -ge 9 ]]; then
    CONVERTED=$(diskutil cs list $LV_UUID | awk '/Conversion Progress/ {print $3;exit}')    
fi
    
ENCRYPTIONEXTENTS=$(diskutil cs list $LV_FAMILY_UUID | awk '/Has Encrypted Extents/ {print $4;exit}')
ENCRYPTION=$(diskutil cs list $LV_FAMILY_UUID | awk '/Encryption Type/ {print $3;exit}')
SIZE=$(diskutil cs list $LV_UUID | awk '/Size \(Total\)/ {print $5,$6;exit}')

if [[ "$corestorage" =~ "is not a CoreStorage" ]] && [[ $boot_filesystem_check = "hfs" ]]; then
    result="$FVVM"
elif [[ ${osvers_major} -eq 10 ]] && [[ ${osvers_minor} -ge 7 ]] && [[ ${osvers_minor} -lt 11 ]]; then
    # This section does checking of the Mac's FileVault 2 status
    # on 10.8.x through 10.10.x
    if [[ "$ENCRYPTIONEXTENTS" = "No" ]]; then
    	result="$FVOFF"
    elif [[ "$ENCRYPTIONEXTENTS" = "Yes" ]]; then
        diskutil cs list $LV_FAMILY_UUID | awk '/Fully Secure/ {print $3;exit}' >> $ENCRYPTSTATUS
	    if grep -iE 'Yes' $ENCRYPTSTATUS 1>/dev/null; then 
	        result="$FVON"
        else
	        if grep -iE 'No' $ENCRYPTSTATUS 1>/dev/null; then
    	        diskutil cs list $LV_FAMILY_UUID | awk '/Conversion Direction/ {print $3;exit}' >> $ENCRYPTDIRECTION
		        if grep -iE 'forward' $ENCRYPTDIRECTION 1>/dev/null; then
	            result="$FVPROGRESS"
                else
	                if grep -iE 'backward' $ENCRYPTDIRECTION 1>/dev/null; then
              	    result="$FVDEGRESS"
                    elif grep -iE '-none-' $ENCRYPTDIRECTION 1>/dev/null; then
                        result="$FVDECRYPTED"
	                fi
                fi
	        fi
	    fi  
    fi
    
# This section does checking of the Mac's FileVault 2 status
# on 10.11.x and 10.12.x 
# If the OS on the Mac is 10.13 or higher, check to see if the
# boot drive is formatted with APFS or HFS+
    
elif [[ ${osvers_major} -eq 10 ]] && [[ ${osvers_minor} -ge 11 ]] && [[ "$boot_filesystem_check" = "hfs" ]]; then
    if [[ "$ENCRYPTION" = "None" ]] && [[ $(diskutil cs list "$LV_UUID" | awk '/Conversion Progress/ {print $3;exit}') == "" ]]; then
        result="$FVOFF"
    elif [[ "$ENCRYPTION" = "None" ]] && [[ $(diskutil cs list "$LV_UUID" | awk '/Conversion Progress/ {print $3;exit}') == "Complete" ]]; then
        result="$FVON"
    elif [[ "$ENCRYPTION" = "AES-XTS" ]]; then
        diskutil cs list $LV_FAMILY_UUID | awk '/High Level Queries/ {print $4,$5;exit}' >> $ENCRYPTSTATUS
        if grep -iE 'Fully Secure' $ENCRYPTSTATUS 1>/dev/null; then 
	        result="$FVON"
        else
	        if grep -iE 'Not Fully' $ENCRYPTSTATUS 1>/dev/null; then
	            if [[ $(diskutil cs list "$LV_FAMILY_UUID" | awk '/Conversion Status/ {print $4;exit}') != "" ]]; then 
	                diskutil cs list $LV_FAMILY_UUID | awk '/Conversion Status/ {print $4;exit}' >> $ENCRYPTDIRECTION
	                if grep -iE 'forward' $ENCRYPTDIRECTION 1>/dev/null; then
		                result="$FVPROGRESS"
		            elif grep -iE 'backward' $ENCRYPTDIRECTION 1>/dev/null; then
	                    result="$FVDEGRESS"
	                fi
	            elif [[ $(diskutil cs list "$LV_FAMILY_UUID" | awk '/Conversion Status/ {print $4;exit}') == "" ]]; then
	                if [[ $(diskutil cs list "$LV_FAMILY_UUID" | awk '/Conversion Status/ {print $3;exit}') == "Complete" ]]; then
	                result="$FVDECRYPTED"
		            fi
		        fi
	        fi
        fi  
    fi
elif [[ ${osvers_major} -eq 10 ]] && [[ ${osvers_minor} -ge 13 ]] && [[ "$boot_filesystem_check" = "apfs" ]]; then
    ENCRYPTSTATUS=$(fdesetup status | xargs)
    if [[ -z $(echo "$ENCRYPTSTATUS" | awk '/Encryption | Decryption/') ]]; then
        ENCRYPTSTATUS=$(fdesetup status | head -1)
        result="$ENCRYPTSTATUS"
    else
        ENCRYPTSTATUS=$(fdesetup status | tail -1)
        result="$ENCRYPTSTATUS"
    fi
else
    result="FV2 status: error"
fi

# add a separate arg for macOS 11, this has been tested as working on a MBPro with Touch ID
if [[ ${osvers_major} -eq 11 ]] && [[ "$boot_filesystem_check" = "apfs" ]]; then
    ENCRYPTSTATUS=$(fdesetup status | xargs)
    if [[ -z $(echo "$ENCRYPTSTATUS" | awk '/Encryption | Decryption/') ]]; then
        ENCRYPTSTATUS=$(fdesetup status | head -1)
        result="$ENCRYPTSTATUS"
    else
        ENCRYPTSTATUS=$(fdesetup status | tail -1)
        result="$ENCRYPTSTATUS"
    fi
else
    result="FV2 status: error"
fi

# Remove the temp files created during the script

if [ -f "$CORESTORAGESTATUS" ]; then
   rm -f "$CORESTORAGESTATUS"
fi

if [ -f "$ENCRYPTSTATUS" ]; then
   rm -f "$ENCRYPTSTATUS"
fi

if [ -f "$ENCRYPTDIRECTION" ]; then
   rm -f "$ENCRYPTDIRECTION"
fi

echo "$result written to EA: $ea_name"

xmlString="<?xml version=\"1.0\" encoding=\"UTF-8\"?><computer><extension_attributes><extension_attribute><name>$ea_name</name><value>$result</value></extension_attribute></extension_attributes></computer>"

curl \
    -s \
    -u ${apiUser}:${apiPass} \
    -X PUT \
    -H "Content-Type: text/xml" \
    -d "${xmlString}" "${jamfURL}/JSSResource/computers/udid/$udid"

echo "$result written to EA: $ea_name"

exit 0
