#!/bin/sh  
# jjourney 09/2016
# single button to install apps, lets you choose what apps you want to install
# Forces some apps
# Eventually this will be re-written in swift with an app

## Update 12/6/2016 
# macs that were re-imaging were having issues with the cert chain, preventing them from managing or having valid API call. 
# Forcing the enrMacsCert trigger and a jamf manage before anything else.

# variables
jamfBin="/usr/local/jamf/bin/jamf"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
CocoaD="/Library/RTS/CD/CocoaDialog3.app/Contents/MacOS/CocoaDialog"
# these are triggered at the end, after a recon
location_trigger="enrRenameMac"
bind_trigger="enrBindMachine"
encrypt_trigger="enrAutoEncryption"

# JSS triggers
CD3_trigger="polCocoaDialog3"
CD2_trigger="polCocoaDialog"

$jamfBin policy -trigger "$CD3_trigger"
$jamfBin policy -trigger "$CD2_trigger"

###### Exit if CD not found ######
# Will try and download Cocoa Dialog policy with trigger listed
# loop
i=1
while [[ ! -f "$CocoaD" ]] && [[ $i -ne 4 ]]
do
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "Error" \
        -description "Dependencies for the rest of this script not found with install. This is try number $i to download dependencies..." \
        -lockHUD \
        -timeout 10 \
        -countdown
    $jamfBin policy -trigger "$CD3_trigger"
    i=$(( $i + 1 ))
    echo "trying to download"
done

if [[ $i -eq 4 ]]; then
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "Error" \
        -description "Dependencies not able to be downloaded. Please contact your administrator" \
        -button1 "OK" \
        -lockHUD
    exit 1
fi

### triggers
### If you want to add more policies, create a new policy with 'Custom' Trigger and trigger name 'enr%identifier%'

## The following 2 run early to account for issues with re-images 
"$jamfBin" policy -trigger enrCompMacsCert
"$jamfBin" manage

# Enter possible choices below. Names must be in order with the trigger_choose
jamfTrigger_Choose=(enrDropboxInstall \
        enrFireFoxInstall \
        enrChromeInstall \
        enrOffice2016InstallNew \
        enrReaderInstall \
        enrVPNInstall \
        )
jamfApp_Choose=(Dropbox \
        Firefox \
        Chrome \
        "Office 2016" \
        "Reader DC" \
        "Cisco VPN" \
        )

## Enter forced policies below. Names must match up with the trigger_force
# Excludes "Change location in JSS" and "rename and bind" as that happens at the end, it is just listed here for information
# New Forced triggers must be listed above "Change location in JSS"/"enrChangeLocation"
jamfTrigger_Force=(enrCasperCheckInstall \
        enrAvastSecurity \
        enrBomgar \
        enrFileVault2Auth \
        )
jamfApp_Force=(CasperCheck \
        "Avast Antivirus" \
        "Bomgar Remote Support" \
        "File-Vault 2 auto-auth" \
        "Add admin account" \
        "Change location in JSS" \
        "Rename and Bind" \
        "Start Encryption" \
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
echo "\\============ Location, Name and Binding ================\\"
# Bind machine
$jamfBin policy -trigger "$bind_trigger"

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
