#!/bin/bash

# jjourney 06/2018
# gives user prompts to update/upgrade to Acrobat Pro DC (versioning sucks!)
# this one is specifically for installing Acrobat Pro DC
# will uninstall Acrobat Pro XI and Acrobat Pro 2015 (classic track?) if present

### Setup ###
# have a policy for installing Acrobat Pro DC with a custom trigger
# scope this policy to any machines that have a version of Acrobat below that version
# fill in parameters
# set it off

# jamf parameters
app_friendly="${4}" # you could hard-code this to "Adobe Acrobat", but I like having the info in the policy
app_version_install="${5}" # you could also hard-code this to "DC", but I like having the info in the policy
install_trigger="${6}" # the trigger for your installer policy
IT_Contact="${7}" # contact info for the message
#="${8}" 
#="${9}" 
#="${10}"
#="${11}"


full_app_add="/Applications/Adobe Acrobat $app_version_install/$app_friendly.app"
XIremove="/Applications/Adobe Acrobat XI Pro/$app_friendly Pro.app"
DCremove="/Applications/Adobe Acrobat 2015/$app_friendly.app"

2015_Uninstall () {
    Acrobat2015_Uninstaller="/Applications/Adobe Acrobat 2015/Adobe Acrobat.app/Contents/Helpers/Acrobat Uninstaller.app/Contents/Library/LaunchServices/com.adobe.Acrobat.RemoverTool"
    if [[ -e "$Acrobat2015_Uninstaller" ]]; then
        echo "Removing Acrobat 2015 Pro"
        "$Acrobat2015_Uninstaller" "/Applications/Adobe Acrobat 2015/Adobe Acrobat.app"
    else
        echo "Acrobat 2015 Pro not installed or Remover Tool not there"
    fi
}

XI_Uninstall () {
    AcrobatXI_Uninstall="/Applications/Adobe Acrobat XI Pro/Adobe Acrobat Pro.app/Contents/Support/Acrobat Uninstaller.app/Contents/MacOS/RemoverTool"
    if [[ -e "$AcrobatXI_Uninstall" ]]; then
        echo "Removing Acrobat XI Pro"
        "$AcrobatXI_Uninstall"
    else
        echo "Acrobat XI Pro not installed or Remover Tool not there"
    fi
}

# local parameters
jamfBin=$(which jamf)
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
warningicon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
description_update="$app_friendly is out of date and the newest version contains important security updates. 

Press update to quit $app_friendly and install the new version, or press later to be notified at a later time. $app_friendly will re-open when installation is complete.

Please save all work in $app_friendly before clicking update.

Please contact $IT_Contact with any questions." 

description_upgrade_open="The installed version of $app_friendly is out of support and has many security risks.

Press upgrade to quit $app_friendly XI Pro and install $app_friendly Pro DC, or press later to be notified at a later time. $app_friendly will re-open when installation is complete.

Please save all work in $app_friendly before clicking update.

Please contact $IT_Contact with any questions."

description_upgrade_closed="The installed version of $app_friendly is out of support and has many security risks.

Press upgrade to uninstall $app_friendly XI Pro and install $app_friendly Pro DC, or press later to be notified at a later time. 

Please contact $IT_Contact with any questions."

# Message for appropriate 
if [[ -e "$XIremove" ]]; then
    echo "XI found, choosing appropriate message for user"
    XIinstalled="1"
    button="Upgrade"
    else
    echo "XI not found, choosing appropriate message for user"
    description="$description_update"
    XIinstalled="0"
    button="Update"
fi

runTheThings () {
    $jamfBin policy -event "$install_trigger"
    XI_Uninstall
    2015_Uninstall
    $jamfBin recon &
}

# first see if we're upgrading to a new version
if [[ "$XIinstalled" -eq 0 ]]; then
    # assumes XI Pro not installed, will attempt to update in background
    if ! pgrep -f "$app_friendly" &>/dev/null; then
        echo "XI not installed, $app_friendly not running"
        # installs trigger
        # uninstall XI if present
        # jamf recon
        runTheThings
    else
        User_Choice=$("$jamfHelper" \
            -windowType utility \
            -icon "$warningicon" \
            -heading "Application $button - $app_friendly" \
            -description "$description" \
            -button1 "$button" \
            -button2 "Later" \
            -defaultButton 1)
        if [[ "$User_Choice" = "0" ]]; then
                echo "User said now"
                # quit app
                pkill -f "$app_friendly" 

                # installs trigger
                # uninstall XI if present
                # jamf recon
                runTheThings
                
                # re-open the app
                open "$full_app_add"
            elif [[ "$User_Choice" = "2" ]]; then
                echo "User said later"
        fi
    fi
elif [[ "$XIinstalled" -eq 1 ]]; then
    # assumes XI Pro is installed, will notify regardless
    if ! pgrep -f "$app_friendly" &>/dev/null; then
        echo "XI installed, $app_friendly not running"
        description="$description_upgrade_closed"
        User_Choice=$("$jamfHelper" \
            -windowType utility \
            -icon "$warningicon" \
            -heading "Application $button - $app_friendly" \
            -description "$description" \
            -button1 "$button" \
            -button2 "Later" \
            -defaultButton 1)
        if [[ "$User_Choice" = "0" ]]; then
                echo "User said now"
                # quit app
                pkill -f "$app_friendly" 

                # installs trigger
                # uninstall XI
                # jamf recon
                runTheThings
            elif [[ "$User_Choice" = "2" ]]; then
                echo "User said later"
        fi
    else
        echo "XI installed, $app_friendly running"
        description="$description_upgrade_open"
        User_Choice=$("$jamfHelper" \
            -windowType utility \
            -icon "$warningicon" \
            -heading "Application $button - $app_friendly" \
            -description "$description" \
            -button1 "$button" \
            -button2 "Later" \
            -defaultButton 1)
        if [[ "$User_Choice" = "0" ]]; then
                echo "User said now"
                # quit app
                pkill -f "$app_friendly" 

                # installs trigger
                # uninstall XI
                # jamf recon
                runTheThings

                # re-open the app
                open "$full_app_add"
            elif [[ "$User_Choice" = "2" ]]; then
                echo "User said later"
        fi
    fi
fi
exit 0
