#!/bin/sh
# jjourney (@koalatee) 07/2016
# Changes name and icns of Self Service.app
# Assumes files are on desktop of logged in user
# 
# 2/2018 
# This is deprecated with jamf 10 branding support

### Setup information:
# Need to already have created .icns files with $newName - see:
# https://developer.apple.com/library/mac/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html
# Files go on desktop
# 
# Input newName
# Once complete, package in composer

# user (for location)
loggedInUser=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Can change the variables below:
################################################################################

# App Name
newName=""
# information only for error messages
icnFileLocation=""
# Location of files
workingLocation="/Users/$loggedInUser/Desktop"

# file locations
ogSelfService="$workingLocation/Self Service.app"
icns="$workingLocation/$newName.icns"
icns2x="$workingLocation/$newName@2x.icns"

# Should not need to change anything after here:
################################################################################
# first check for all files:
# Self Service to upgrade
if [[ -d "$ogSelfService" ]]; then
    echo "Self Service found, continuing..."
else
    echo "Original Self Service.app not present, download from JSS and place on desktop."
    exit 1
fi

# check for .icns
if [[ -f "$icns" ]]; then
    echo "$newName.icns found, continuing..."
else
    echo "\"$newName.icns\" not found, download from $icnFileLocation and place in $workingLocation."
    exit 1
fi

# and for @2x.icns
if [[ -f "$icns2x" ]]; then
    echo "$newName@2x.icns found, continuing..."
else
    echo "\"$newName@2x.icns\" not found, download from $icnFileLocation and place in $workingLocation."
    exit 1
fi

echo "all files found, continuing..."

###################################
# Everything is found, start edit #
###################################
# modify plist file with $newName
# copy
cp "$ogSelfService/Contents/info.plist" "$workingLocation"
plist="$workingLocation/info.plist"
# convert to xml
plutil -convert xml1 "$plist"

# edit <key>CFBundleName</key>
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleName $newName" "$plist"
# edit <key>CFBundleIconFile</key>
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $newName.icns" "$plist"
echo "plist updated with $newName"


# modify .nib to change menu items to $newName
# copy
cp "$ogSelfService/Contents/Resources/MainMenu.nib" "$workingLocation"
nib="$workingLocation/MainMenu.nib"
# turn into xml and provide permissions
plutil -convert xml1 "$nib"
chmod 777 "$nib"
# replace all 'Self Service' with '$newName'
sed -i '' "s/Self Service/$newName/g" "$nib"
echo "MainMenu.nib updated with $newName"


# modify localizable.strings for error messages with $newName
# copy
cp "$ogSelfService/Contents/Resources/en.lproj/Localizable.strings" "$workingLocation"
localize="$workingLocation/Localizable.strings"
# turn into xml and provide permissions
plutil -convert xml1 "$localize"
chmod 777 "$localize"
# replace all 'Self Service' with '$newName'
sed -i '' "s/Self Service/$newName/g" "$localize"
echo "localizable.strings updated with $newName"

# make sure permissions are correct
chmod 744 "$plist"
chmod 744 "$nib"
chmod 744 "$localize"

#####################################
# Everything is modified, copy back #
#####################################

# copy info.plist back into Self Service.app
cp -f "$plist" "$ogSelfService/Contents/"
rm -rf "$plist"
echo "modified plist moved to $ogSelfService"

# copy mainmenu.nib back into Self Service.app
cp -f "$nib" "$ogSelfService/Contents/Resources/"
rm -rf "$nib"
echo "modified .nib moved to $ogSelfService"

# copy localized.strings back into Self Service.app
cp -f "$localize" "$ogSelfService/Contents/Resources/en.lproj/"
rm -rf "$localize"
echo "modified localized.strings moved to $ogSelfService"

# copy icns into Self Service.app
cp "$icns" "$ogSelfService/Contents/Resources"
cp "$icns2x" "$ogSelfService/Contents/Resources"
echo "icns moved to $ogSelfService"

# remove Self Service.icns
rm -rf "$ogSelfService/Contents/Resources/Self Service.icns"
rm -rf "$ogSelfService/Contents/Resources/Self Service@2x.icns"
echo "old icns removed"

# rename Self Service.app and move into /Applications for easy packaging
mv "$ogSelfService" "/Applications/$newName.app"
chown root:wheel "/Applications/$newName.app"
chmod -R 755 "/Applications/$newName.app"
echo "app renamed to $newName"
echo "chown root:wheel and chmod 755 permissions applied"

# User message
"$jamfHelper" \
    -windowType hud \
    -alignDescription center \
    -title "Next Steps" \
    -description "Now package this in composer to distribute to users" \
    -button1 "OK" \
    -defaultButton 1 \
    -lockHUD

open /Applications

exit 0
