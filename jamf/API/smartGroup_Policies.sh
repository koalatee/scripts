#!/bin/sh

# You can input a smart group and it will search all policies to see what it is scoped to.
 
### Issues:
# Output not that neat, will update at some point
# currently requires hardcoding of max policy ID (line 27)
###

###### Variables ######
# System
CocoaD="/Library/$company/CD/CocoaDialog.app/Contents/MacOS/CocoaDialog"
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
domain=""
jamfBin="/usr/local/jamf/bin/jamf"

# Output information and location
loggedInUser="$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')"
Output="/Users/$loggedInUser/Desktop/policies+scope.csv"

# JSS
jss="https://your.jss.here:8443"
CD2_trigger="polCocoaDialog"

# Max policy ID + 1
max_id=502

# What policy name are we looking for?
look_for=""

if [[ -z $look_for ]]; then
    look_for_full="$($CocoaD standard-inputbox \
        --title "ENTER A WORD" \
        --informative-text "This can be a keyword or a specific name. Searches Computer Groups - include or exclude - only." \
        --button1 "OK" \
        --button2 "Cancel" \
        --float \
        --value-required \
        --string-output \
        )"
    if [[ "$look_for_full" =~ "Cancel" ]]; then
        exit 0
    fi
    look_for=${look_for_full:3}
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

i=1

while [[ $i -ne $max_id ]]
do
    current_policy="$(curl \
        -s \
        -v \
        -u ${username}:${password} \
        -X GET $jss/JSSResource/policies/id/$i \
        -H "Accept:application/xml" \
        )"
    policy_name="$(echo $current_policy \
        |xpath "/policy/general/name" \
        )"
    
    policy_scope_include="$(echo $current_policy \
        |xpath "/policy/scope/computer_groups" \
        )" 
    policy_scope_exclude="$(echo $current_policy \
        |xpath "/policy/exclusions" \
        )"
        
        if [[ "$policy_scope_include" =~ "$look_for" ]]; then
            echo "$policy_name is scoped to $policy_scope_include" >> "$Output"
        fi
        
        if [[ "$policy_scope_exclude" =~ "$look_for" ]]; then
            echo "$policy_name has an exclusion to $policy_scope_exclude" >> "$output"
        fi
i=$(($i+1))
done
