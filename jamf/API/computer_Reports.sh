#!/bin/bash
##
## jjourney 04/2017
##
## puts all computers with the following fields into a csv file for each dept:
## Folder 1 ($Output_Folder)
## JSS ID, DEPARTMENT NAME, MACHINE NAME, PRIMARY USER, 
## Folder 2 ($Output_FolderEA)
## FULL NAME, LAST CHECK-IN DATE, FV2 STATUS, EA INFO
## 
## only requirements are Cocoa Dialog for username/password (line 49-82)
## For 520 machines, it takes around 10 minutes. I need to re-write this in another language :D

###### Variables ######
### change these variables
# JSS
jss=""

# domain (for text dialog of username/password input only)
domain=""

# EA ID you want to look at?
# the name will be grabbed automatically
EA_ID=
# Friendly name of EA?
EA_NAME=""

# Where is Cocoa Dialog?
CocoaD=""

## No need to change below here
# System
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamfBin="/usr/local/jamf/bin/jamf"

# total number of machines (for error checking) 
Machine_count=0

# Output information and location
loggedInUser="$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')"
month=$(date '+%m')
year=$(date '+%Y')
Output_Folder="/Users/$loggedInUser/Desktop/MacOS Dept Report $month-$year"
Output_FolderEA="/Users/$loggedInUser/Desktop/MacOS Dept $EA_NAME Report $month-$year"

if [[ ! -d "$Output_Folder" ]]; then
    mkdir "$Output_Folder"
fi

if [[ ! -d "$Output_FolderEA" ]]; then
    mkdir "$Output_FolderEA"
fi

###### User info ######
# Get Username
username_Full="$($CocoaD standard-inputbox \
    --title "$domain ID" \
    --informative-text "Please enter your $domain ID" \
    --empty-text "Please type in your $domain before clicking OK." \
    --button1 "OK" \
    --button2 "Cancel" \
    --float \
    --value-required \
    --string-output \
)"
if [[ "$username_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
username=${username_Full:3}

# Get Password
password_Full="$($CocoaD secure-inputbox \
    --title "$domain Password" \
    --informative-text "Please enter your $domain Password" \
    --empty-text "Please type in your $domain Password before clicking OK." \
    --button1 "OK" \
    --button2 "Cancel" \
    --float \
    --value-required \
    --string-output \
)"
if [[ "$password_Full" =~ "Cancel" ]]; then
    exit 0
    echo "user cancelled"
fi
password=${password_Full:3} 

##
####### Get all computer data

# Get EA name
EA_NAME="$(curl \
    -s \
    -u ${username}:${password} \
    -X GET $jss/JSSResource/computerextensionattributes/id/$EA_ID \
    -H "Accept: application/xml" \
    |xpath /computer_extension_attribute/name \
    |sed -e 's/<name>//;s/<\/name>//' \
    )"

# Get all machine data
api_AllComputersRaw="$(curl \
    -s \
    -u ${username}:${password} \
    -X GET $jss/JSSResource/computers/subset/basic \
    -H "Accept: application/xml" \
    )"
# Put machines in array
api_AllComputerNames="$(echo $api_AllComputersRaw \
        |xpath "/computers/computer[managed = 'true']/id" \
        |sed -e 's/ /_/g' \
        |sed -e 's/<id>//g;s/<\/id>/ /g' \
        )"
comp_allArray=($api_AllComputerNames)

# Loop through all machines
for machine in ${comp_allArray[@]}
do
    computer_data="$(curl \
        -s \
        -u ${username}:${password} \
        -X GET $jss/JSSResource/computers/id/$machine \
        -H "Accept: application/xml" \
        )"
    # Is this machine active and managed?    
    managed="$(echo $computer_data \
            | xpath "/computer/general/remote_management/managed" )"
    # Get all the info
    ## Error checking on managed status...?
    if [[ $managed =~ "false" ]]; then
        echo "$current is not a valid machine, or is un-managed"
    else
        Machine_count=$(($Machine_count+1))
        ID="$(echo $computer_data \
            | xpath "/computer/general/id" \
            | sed -e 's/<id>//g;s/<\/id>//g' \
            )"
        DEPT="$(echo $computer_data \
            | xpath "/computer/location/department" \
            | sed -e 's/<department>//g;s/<\/department>//g' \
            )"
            # set blank dept to the same dept
            if [[ $DEPT == "<department />" ]]; then
                DEPT="no dept set"
            fi
        NAME="$(echo $computer_data \
            | xpath "/computer/general/name" \
            | sed -e 's/<name>//g;s/<\/name>//g' \
            )"
        MODEL="$(echo $computer_data \
            | xpath "/computer/hardware/model" \
            | sed -e 's/<model>//g;s/<\/model>//g' \
            )"
        USER="$(echo $computer_data \
            | xpath "/computer/location/username" \
            | sed -e 's/<username>//g;s/<\/username>//g' \
            )"
        FULL_NAME="$(echo $computer_data \
            | xpath "/computer/location/realname" \
            | sed -e 's/<realname>//g;s/<\/realname>//g' \
            )"
        CHECK_IN="$(echo $computer_data \
            | xpath "/computer/general/last_contact_time" \
            | sed -e 's/<last_contact_time>//g;s/<\/last_contact_time>//g' \
            )"
            if [[ $CHECK_IN == "<last_contact_time />" ]]; then
                CHECK_IN="No successful check-in"
            fi
        FV_CHECK="$(echo $computer_data \
            | xpath "/computer/hardware/filevault2_users/user" \
            | sed -e 's/<name>//g;s/<\/name>//g' \
            )"
            if [[ ! $FV_CHECK ]]; then
                FV_STATUS="Not encrypted"
            else
                FV_STATUS="Encrypted"
            fi

        EA="$(echo $computer_data \
            | xpath "/computer/extension_attributes/extension_attribute[id = '$EA_ID']/value" \
            | sed -e 's/<value>//g;s/<\/value>//g' \
            )"
            if [[ $EA == "<value />" ]]; then
                EA="Unsure of status"
            else
                if [[ ! $EA =~ "Not Installed" ]]; then
                # Output with EA
                EA_Output="$Output_FolderEA"/"$DEPT".csv
                    if [[ ! -f $EA_Output ]]; then
                        # Set column names
                        echo "MACHINE NAME,PRIMARY USER,FULL NAME,$EA_NAME" >> "$EA_Output"
                    fi
                    echo "$NAME,$USER,$FULL_NAME,$EA" >> "$EA_Output"
                echo "echoing $EA into output"
                fi
            fi
        
        # Output without EA
        Output="$Output_Folder"/"$DEPT".csv
            if [[ ! -f $Output ]]; then
                # Set column names
                echo "DEPARTMENT,FULL NAME,COMPUTER NAME,PRIMARY USER,LAST CHECK-IN DATE,FV2 STATUS,MAC MODEL" >> "$Output"
            fi
        echo "$DEPT,$FULL_NAME,$NAME,$USER,$CHECK_IN,$FV_STATUS,$MODEL" >> "$Output"
    fi
done

chmod -R 777 "$Output_Folder"
chmod -R 777 "$Output_FolderEA"
open "/Users/$loggedInUser/Desktop"

echo "Ran on $Machine_count machines"

exit 0
