#!/bin/bash
######   Notes   ######
#
# Binding to AD
# jjourney 07/2016
#
# Per the $DomainC, this only searches within the $main OU
# For each OU, it looks if there are sub-OUs and asks which you want to join
# User is prompted to rename the machine if they want, which will also scutil --set LocalHostName and HostName
# 
# This also checks to see if the machine is already bound
# If already bound, will force an unbind before binding again
# Unbind options are "Leave" which keeps the AD object, or "Remove" which deletes the AD object
#
# UPDATE 09/30/2016
# Remove API name change from binding in case passwords are not allowed
# Call the 'rename' script instead

###### Variables ######
# System
CocoaD="" # cocoa dialog binary location
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamfBin="/usr/local/jamf/bin/jamf"

# JSS
jss=""
CD2_trigger="polCocoaDialog"
rename_trigger="enrRenameMac"
forceName_trigger="polForceName"

## AD variables 
adUser="" # user (should be a service account) to do some checks
domain="" # short name for domain (for user input)
domainFull="" # your.domain.here
DomainC="ou=$OU_main,dc=$dc_info_here" # where do you want to start looking?
domainPreferred="" # what DC do you want to be preferred

###### Exit if CD not found ######
# Will try and download Cocoa Dialog policy with trigger listed
$jamfBin policy -trigger "$CD2_trigger"
# loop
i=1
while [[ ! -f "$CocoaD" ]] && [[ $i -ne 4 ]]
do
    "$jamfHelper" \
        -windowType hud \
        -alignDescription center \
        -title "Error" \
        -description "Dependencies needed for the script not found with install. This is try number $i to download dependencies..." \
        -lockHUD \
        -timeout 10 \
        -countdown
    $jamfBin policy -trigger "$CD2_trigger"
    i=$(( $i + 1 ))
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
###### check if machine is already bound, ask for unbind before continuing
##   
Rebind_Check="$(dsconfigad -show | awk '/Active Directory Domain/{print $NF}')"
# If the domain is correct
if [ "$Rebind_Check" == "$domainFull" ]; then
    # Check ID of $aduser
    id -u $adUser
    # If check is successful
    if [[ $? =~ "no such user" ]]; then
        echo "Mac not bound to AD"
    else
        # Force re-binding to AD, -leave or -remove
        AD_Plist="/Library/Preferences/OpenDirectory/Configurations/Active Directory/"
        Rebind_Full="$($CocoaD \
            msgbox \
            --title "UnBind Machine" \
            --text "Please choose:" \
            --informative-text "This machine is already bound. Re-bind is recommended. 'Leave' will unbind before continuing and preserve the AD record; 'Remove' will unbind and delete the object from AD; 'Exit' will cancel and exit." \
            --no-cancel \
            --float \
            --button1 "Leave" \
            --button2 "Remove" \
            --button3 "Exit" \
        )"
            # Chose 'No'
            if [ "$Rebind_Full" -eq 3 ]; then
                exit 1
            # Chose 'Remove'
            elif [ "$Rebind_Full" -eq 2 ]; then
                echo "$domain chose to unbind machine, delete object"
                dsconfigad \
                    -remove \
                    -force \
                    -u "${username}" \
                    -p "${password}"
                $CocoaD \
                    ok-msgbox \
                    --title "Machine Deleted" \
                    --text "Action required" \
                    --informative-text "The machine has been removed from AD. Please make sure you add any descriptions or join to any groups needed when re-joining." \
                    --float \
                    --no-cancel
                sleep 5
                rm -rf "$AD_Plist"
            # Chose 'Leave'
            elif [ "$Rebind_Full" -eq 1 ]; then
                echo "$username chose to unbind machine; keep object"
                dsconfigad \
                    -leave \
                    -localuser "${username}" \
                    -localpassword "${password}"
                sleep 15
                rm -rf "$AD_Plist"
                v=2
            else 
                echo "messed up"
                exit 0
            fi
    fi
else 
    echo "Mac not bound to AD"
fi
        
#### make sure computer name is correct ######
# Only change name if it is a new bind; existing bind will maintain name
if [[ $v -eq 2 ]]; then
$CocoaD \
    ok-msgbox \
    --title "Unbind complete" \
    --text "Computer Name Set" \
    --informative-text "The computer object still exists in AD. The name is set to $computerName and the machine will re-join its object." \
    --float \
    --no-cancel
else
# ask if user wants to change it
computerName_prompt="$($CocoaD \
    yesno-msgbox \
    --title "Change Name?" \
    --text "Please Choose:" \
    --informative-text "The current name is $computerName. Would you like to change it before continuing?" \
    --float \
    --no-cancel \
)"
fi

# Prompt if the user says 'yes' to changing name
if [[ "$computerName_prompt" == "1" ]]; then
    $jamfBin policy -trigger "$rename_trigger"
fi

$jamfBin policy -trigger "$forceName_trigger"
computerName="$(scutil --get ComputerName)"

# change HostName and change LocalHostName
sudo scutil --set LocalHostName "$computerName"
sudo scutil --set HostName "$computerName"
echo "set LocalHostName and HostName"

##
###### name check now done ######
##

n=1
## repeat??
while [[ $n -ne 3 ]]
do
#### Dropdowns for which OU to join to
## OU's under $main ou
## OU_UserGroup - our user groups are based off of the OU name. 
## If you don't need admin, can go ahead and delete these references.
AD_OUs="$(ldapsearch \
    -H ldap://$domainFull \
    -D ${username}@$domainFull \
    -w ${password} \
    -b "$DomainC" \
    -s one o dn \
    | grep 'dn: OU=' \
    | awk -F= '{ split($2,arr,","); print arr[1] }' \
)"

# Ask which main OU you want to join
OU_OneFull="$($CocoaD \
    standard-dropdown \
    --title "Main OU" \
    --text "Select a main OU to join" \
    --items $AD_OUs \
    --float \
    --no-cancel \
    --string-output \
)"
OU_One=${OU_OneFull:3}

## OU's under $OU_One 
# curently looks 4 deep. 
# If more are needed, need another if statement
AD_Two_OUs="$(ldapsearch \
        -H ldap://$domainFull \
        -D ${username}@$domainFull \
        -w ${password} \
        -b "ou=$OU_One,$DomainC" \
        -s one o dn \
        | grep 'dn: OU=' \
        | awk -F= '{ split($2,arr,","); print arr[1] }' \
)"

## Begin mining the depths ############## if 1
if [ -z "$AD_Two_OUs" ]; then
    echo "OUs parsed"
    OU_JoinFinal="ou=$OU_One,$DomainC"
    OU_UserGroup="$OU_One"
else
    # Ask which OU (sub $OU_One) you want to join
    # Add $OU_One to $AD_Two_OUs options
    AD_Two_OUs="$OU_One $AD_Two_OUs"
    
    OU_TwoFull="$($CocoaD \
        standard-dropdown \
        --title "AnOUther OU" \
        --text "Select a sub OU to join" \
        --items $AD_Two_OUs \
        --float \
        --string-output \
        --no-cancel \
    )"
    OU_Two=${OU_TwoFull:3}
    
    # Check next level
    AD_Three_OUs="$(ldapsearch \
        -H ldap://$domainFull \
        -D ${username}@$domainFull \
        -w ${password} \
        -b "ou=$OU_Two,ou=$OU_One,$DomainC" \
        -s one o dn \
        | grep 'dn: OU=' \
        | awk -F= '{ split($2,arr,","); print arr[1] }' \
    )"
    # next ############## if 2
    if [ -z "$AD_Three_OUs" ]; then
        echo "OUs parsed"
        if [[ "$OU_One" == "$OU_Two" ]]; then
            OU_JoinFinal="ou=$OU_One,$DomainC"
            OU_UserGroup="$OU_One"
        else
            OU_JoinFinal="ou=$OU_Two,ou=$OU_One,$DomainC"
            OU_UserGroup="$OU_Two"
        fi
    else
        # Ask which OU (sub $OU_Two) you want to join 
        # Add $OU_Two to $AD_Three_OUs options
        AD_Three_OUs="$OU_Two $AD_Three_OUs"
        
        OU_ThreeFull="$($CocoaD \
            standard-dropdown \
            --title "S[OU]b-day fun-day" \
            --text "Don't go too deep, you'll awaken the Balrog" \
            --items $AD_Three_OUs \
            --float \
            --string-output \
            --no-cancel \
        )"
        OU_Three=${OU_ThreeFull:3}
        
        # We have to go deeper ############## if 3
        AD_Four_OUs="$(ldapsearch \
            -H ldap://$domainFull \
            -D ${username}@$domainFull \
            -w ${password} \
            -b "ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC" \
            -s one o dn \
            | grep 'dn: OU=' \
            | awk -F= '{ split($2,arr,","); print arr[1] }' \
        )"
        # how far can we go?
        if [ -z "$AD_Four_OUs" ]; then
            echo "OUs parsed"
            if [[ "$OU_Two" == "$OU_Three" ]]; then
                OU_JoinFinal="ou=$OU_Two,ou=$OU_One,$DomainC"
                OU_UserGroup="$OU_Two"
            else
                OU_JoinFinal="ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
                OU_UserGroup="$OU_Three"
            fi
        else
            # Ask which OU (sub $OU_Two) you want to join 
            # Add $OU_Three to $AD_Four_OUs options
            AD_Four_OUs="$OU_Three $AD_Four_OUs"
        
            OU_FourFull="$($CocoaD \
                standard-dropdown \
                --title "Durin's Bane" \
                --text "Drums in the Deep : Khazad Dum" \
                --items $AD_Four_OUs \
                --float \
                --string-output \
                --no-cancel \
            )"
            OU_Four=${OU_FourFull:3}
        # we're done?
        
        # idk just another check ############## if 4
        AD_Five_OUs="$(ldapsearch \
            -H ldap://$domainFull \
            -D ${username}@$domainFull \
            -w ${password} \
            -b "ou=$OU_Four,ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC" \
            -s one o dn \
            | grep 'dn: OU=' \
            | awk -F= '{ split($2,arr,","); print arr[1] }' \
        )"
            # how far can we go?
            if [ -z "$AD_Five_OUs" ]; then
                echo "OUs parsed"
                if [[ "$OU_Three" == "$OU_Four" ]]; then
                    OU_JoinFinal="ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
                    OU_UserGroup="$OU_Three"
                else
                    OU_JoinFinal="ou=$OU_Four,ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
                    OU_UserGroup="$OU_Four"
                fi
            else
            # Ask which OU (sub $OU_Two) you want to join 
            # Add $OU_Four to $AD_Five_OUs options
            AD_Four_OUs="$OU_Two $AD_Five_OUs"
        
            OU_FiveFull="$($CocoaD \
                standard-dropdown \
                --title "Final stand" \
                --text "I am a servant of the secret fire, wielder of the flame of Anor. You cannot pass. The dark fire will not avail you, flame of Udûn. Go back to the Shadow! You cannot pass." \
                --items $AD_Five_OUs \
                --float \
                --string-output \
                --no-cancel \
            )"
            OU_Five=${OU_FiveFull:3}
            # MAKE IT STOP ############## if done
                if [[ "$OU_Four" == "$OU_Five" ]]; then
                    OU_JoinFinal="ou=$OU_Four,ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
                    OU_UserGroup="$OU_Four"
                else
                    OU_JoinFinal="ou=$OU_Five,ou=$OU_Four,ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
                    OU_UserGroup="$OU_Five"
                fi
            fi
        fi
    fi
fi
# Make $OU_JoinFinal readable
niceOU_Join="$(echo $OU_JoinFinal | sed -e 's/ou=//g;s/,dc=/./g')"

## Make sure this choice is correct
OU_Check="$($CocoaD \
    yesno-msgbox \
    --title "Confirm Selection" \
    --text "Please Choose:" \
    --informative-text "You are attempting to join $computerName to the following location: $niceOU_Join : is this correct?" \
    --float \
    )"
    
if [[ $OU_Check -eq 1 ]]; then
    n=3
elif [[ $OU_Check -eq 2 ]]; then
    n=2
    echo "play that song one more time!"
elif [[ $OU_Check -eq 3 ]]; then
    exit 1
    echo "cancelling script"
fi
done 

##
####### Bind to AD #######
##
# something needed for how our user groups are set up
if [[ "$OU_One" =~ "group 1" ]] || [[ "$OU_One" =~ "group 2" ]]; then
    echo "Not group 3, user group will be $domain\\$OU_One.OUusers"
    Ask_User="$OU_One"
else
    echo "group 3, user group will be $domain\\$OU_UserGroup.OUusers"
    Ask_User="$OU_UserGroup"
fi
    

# ask if you want to add the users in $OU_One as an admin
groupAdmin_Check="$($CocoaD \
    yesno-msgbox \
    --title "Add Users as Admin?" \
    --text "Please Choose:" \
    --informative-text "Do you want the users in $Ask_User to have admin access?" \
    --float \
    --no-cancel \
)"
if [[ "$groupAdmin_Check" -eq 1 ]]; then
    echo "$username selected to allow users in $Ask_User to be admins"
    userAdmin="$domain\\$Ask_User.OUusers"
else
    echo "$username selected to not allow users in $Ask_User to be admins"
    userAdmin=""
fi

# set admin groups
groupAdmin="$domain\\$OU_One.OUAdmins"

# bind to AD
dsconfigad \
    -add "$domainFull" \
    -alldomains disable \
    -computer $computerName \
    -username "${username}" \
    -password "${password}" \
    -mobile enable \
    -mobileconfirm disable \
    -ou "$OU_JoinFinal" \
    -preferred "$domainPreferred" \
    -nogroups \
    -groups "$groupAdmin","$userAdmin" \
    -useuncpath disable \
    -force

# change Search Policy / Authentication
dscl /Search -delete / CSPSearchPath "/Active Directory/$domain/All Domains"
dscl /Search -append / CSPSearchPath "/Active Directory/$domain/$domainFull"
dscl /Search/Contacts -delete / CSPSearchPath "/Active Directory/$domain/All Domains"
dscl /Search/Contacts -append / CSPSearchPath "/Active Directory/$domain/$domainFull"


###### Finished. Success! ######
## New check against AD
nameCheck="$(dsconfigad -show | awk '/Computer Account/ {print $NF}')"
adminCheck="$(dsconfigad -show | awk '/admin groups/ {print $NF}')"
domainCheck="$(dsconfigad -show | awk '/Directory Domain/ {print $NF}')"

$CocoaD \
    msgbox \
    --title "Success!" \
    --text "New AD info:" \
    --informative-text "This computer, $nameCheck, has been bound to $domainCheck. Groups able to administer are $adminCheck" \
    --button1 "That was easy"
exit 0
