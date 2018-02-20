#!/bin/sh  
# jjourney 09/2016
# single button to install apps, lets you choose what apps you want to install
# Option to force some apps

### Setup:
# 
# setup policies with ongoing custom triggers
# input triggers as desired
# jamfTrigger_Choose = input triggers as desired, these are selectable
# jamfApp_Choose = friendly name to match up triggers above (for user display)
# jamfTrigger_Force = input triggers as desired, these are forced
# jamfApp_Force = friendly name to match up forced policies (for user display)
#
###

# variables
jamfBin="/usr/local/jamf/bin/jamf"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
CocoaD="/Path/to/CD/CocoaDialog3.app/Contents/MacOS/CocoaDialog"
# I have these are triggered at the end, after a recon
bind_trigger=""
encrypt_trigger=""

# JSS triggers
CD3_trigger=""

$jamfBin policy -trigger "$CD3_trigger"

### triggers
### If you want to add more policies, create a new policy with 'Custom' Trigger and trigger name 'enr%identifier%'

# Enter possible choices below. Names must be in order with the trigger_choose
jamfTrigger_Choose=(trigger1 \
        trigger2 \
        trigger3 \
        trigger4 \
        trigger5 \
        trigger6 \
        )
jamfApp_Choose=(trigger_1_friendly_name \
        trigger_2_friendly_name \
        trigger_3_friendly_name \
        trigger_4_friendly_name \
        trigger_5_friendly_name \
        trigger_6_friendly_name \
        )

## Enter forced policies below. Names must match up with the trigger_force
# Excludes "Change location in JSS" and "rename and bind" as that happens at the end, it is just listed here for information
# New Forced triggers must be listed above "Change location in JSS"/"enrChangeLocation"
jamfTrigger_Force=(forcetrigger1 \
        forcetrigger2 \
        forcetrigger3 \
        forcetrigger4 \
        )
jamfApp_Force=(forcetrigger1_friendly_name \
        forcetrigger2_friendly_name \
        forcetrigger3_friendly_name \
        forcetrigger4_friendly_name \
        forcetrigger5_friendly_name \
        forcetrigger6_friendly_name \
        )

# Define total array
App_Array=("${jamfApp_Choose[@]}" "${jamfApp_Force[@]}")
# Automatically decide which apps will be forced
Choice_Possible=${#jamfApp_Choose[@]}
Forced_Choices=${#jamfApp_Force[@]}

# Set the jamfArray_Force (forces checked boxes)
t=$(($Forced_Choices + $Choice_Possible))
s=$(($Choice_Possible - 1))
while [[ $t -gt $s ]]; do
    s=$((s+1))
    jamfArray_Force+=($s)
done


echo "\\============ App selection ================\\"
#### Present options to tech
Install_Apps="$("$CocoaD" \
    checkbox \
    --title "Select which apps to install" \
    --items "${App_Array[@]}" \
    --checked "${jamfArray_Force[@]}" \
    --disabled "${jamfArray_Force[@]}" \
    --label "\"Install All\" will install all below. If you do not want some apps installed, check the ones that you do want and select \"Install Selected\"." \
    --width 500 \
    --posY top \
    --string-output \
    --button1 "Install All" \
    --button2 "Install Selected" \
    --float \
    )"
Selected_Apps=${Install_Apps:16}
Selected_Array=($Selected_Apps)

#### Recon before messing with the API
$CocoaD \
    bubble \
    --x-placement center \
    --title "Running recon" \
    --text "Running recon so API works, please wait..." \
    
# Run Recon
$jamfBin recon

echo ""
echo "\\============ App Installation ================\\"
### install apps
if [[ "$Install_Apps" =~ "Install All" ]]; then
    # Run the selected apps
    for eachtrigger in "${jamfTrigger_Choose[@]}"
    do
        echo ""
        echo "installing policy with $eachtrigger trigger..."
        $jamfBin policy -trigger $eachtrigger
        $CocoaD \
            bubble \
            --x-placement center \
            --title "Policy Complete" \
            --text "Policy with trigger $eachtrigger finished..."
        sleep 2s
    done
    # Run the forced apps
    for eachtrigger in "${jamfTrigger_Force[@]}"
    do
        echo ""
        echo "installing policy with $eachtrigger trigger..."
        $jamfBin policy -trigger $eachtrigger
        $CocoaD \
            bubble \
            --x-placement center \
            --title "Policy Complete" \
            --text "Policy with trigger $eachtrigger finished..."
        sleep 2s
    done
elif [[ "$Install_Apps" =~ "Install Selected" ]]; then
    App_Array_Full=("${jamfTrigger_Choose[@]}" "${jamfTrigger_Force[@]}")
    n=0
    while [[ ! -z "${App_Array_Full[$n]}" ]] 
    do
        if [[ "${Selected_Array[$n]}" == "on" ]]; then
            echo ""
            echo "Installing ${App_Array_Full[$n]}"
            $jamfBin policy -trigger "${App_Array_Full[$n]}"
            $CocoaD \
                bubble \
                --x-placement center \
                --title "Policy Complete" \
                --text "Policy with trigger ${App_Array_Full[$n]} finished..."
            sleep 2s
        elif [[ "${Selected_Array[$n]}" == "off" ]]; then
            echo ""
            echo "skipping ${App_Array_Full[$n]}"
        else 
            echo "*****error*****"
        fi
    n=$(( $n + 1 ))
    done
else 
    echo "*****error*****"
fi

# Encrypt machine
$jamfBin policy -trigger "$encrypt_trigger"

$jamfBin recon

$CocoaD \
    msgbox \
    --title "Reboot to finish" \
    --text "Logout" \
    --informative-text "Logout to start encryption. CMD+SHIFT+Q will quickly log you out." \
    --button1 "Finish Setup" \
    --float
    
exit 0
