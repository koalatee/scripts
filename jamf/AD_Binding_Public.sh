#!/bin/bash
######   Notes   ######
#
# Binding to AD
# jjourney 07/2016
#
# Lets you drill down what OU you want to join a mac to
# First choices are listed below in $OU_choices
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
#
# UPDATE 11/2/2016
# Now shows an error message if binding did not happen
#
#
# UPDATE 6/9/2017
# Set the password policy to 180 days, from 45
#
# UPDATE 9/18/2017
# change ldap.conf from
# TLS_REQCERT demand to TLS_REQCERT allow
# changed all ldap:// to ldaps://
#
# UPDATE 11/27/2017
# changed domain preferred from
#
# UPDATE 12/6/2017
# automatically add the autoinstallreceipt.pkg for 802.1x profile
# commented out old ? (end of script)
#
# UPDATE 12/11/2017
# ldapsearch now queries against IP
# IPGET checks all IPs against 
# removes problematic ones, should cut down on time 
#
# UPDATE 06/2018
# adding GIOS as an option
#
# UPDATE 06/2018
# removed cocoa dialog, all applescript
# condensed code, more functions, more readable??
# leave preserves OU location and groups for immediate rebind

###### Variables ######
# System
computerName="$(scutil --get ComputerName)"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamfBin="/usr/local/jamf/bin/jamf"
wifiJAMFreceipt="" # <-- used in our environment as we're slowly bringing macs on the domain and they need to have 802.1x profile

# jamf
jamf="" # <-- input jamf URL here (used for calling another script to change name)
rename_trigger="" # <-- trigger for said name change 
forceName_trigger="" # <-- trigger to force jamf name down to mac

## AD variables 
adUser="" # <-- checks to see if it can find this user to help make sure machine is bound
domain="" # <-- shortname of domain
domainFull="" # <-- fullname of domain
domainPreferred="" # <-- for final binding command
DomainCSuffix="" # <-- used to create $DomainC, want in format dc=company,dc=com
OU_choices="" # these are the OUs you want to choose from in the beginning

## IPGET IP addresses to ignore
# problem IP addresses with ldapsearch, due to round-robin/load balancer/etc
# add any more problem ones into the delete array (below)
delete=()

# applescript
#
# template:
########### Title - "$2" ############
#                                   #
#     Text to display - "$1"        #
#                                   #
#      [Default response - "$5"]    #
#                                   #
#               (B1 "$3") (B2 "$4") # <- Button 2 default
#####################################

function simpleInput() {
osascript <<EOT
tell app "System Events"
text returned of (display dialog "$1" default answer "$5" buttons {"$3", "$4"} default button 2 with title "$2")
end tell
EOT
}

function hiddenInput() {
osascript <<EOT
tell app "System Events" 
text returned of (display dialog "$1" with hidden answer default answer "" buttons {"$3", "$4"} default button 2 with title "$2")
end tell
EOT
}

function 1ButtonInfoBox() {
osascript <<EOT
tell app "System Events"
button returned of (display dialog "$1" buttons {"$3"} default button 1 with title "$2")
end tell
EOT
}

function 2ButtonInfoBox() {
osascript <<EOT
tell app "System Events"
button returned of (display dialog "$1" buttons {"$3", "$4"} default button 2 with title "$2")
end tell
EOT
}

function listChoice() {
osascript <<EOT
tell app "System Events"
choose from list every paragraph of "$5" default items "None" with title "$2" with prompt "$1" OK button name "$4" cancel button name "$3"
end tell
EOT
}

function IPGET() {
domainIPall=($(dig +short $domainFull))
for del in ${delete[@]}
do 
    domainIPall=("${domainIPall[@]/$del}")
done
randomIP=$[$RANDOM % ${#domainIPall[@]}]
domainIP=${domainIPall[$randomIP]}
delete+=($domainIP) # if one fails, it won't try it again
echo "using $domainIP"
}

function LDAPlookup() {
    ldapsearch \
    -H ldaps://$domainIP \
    -D ${domainID}@$domainFull \
    -w ${password} \
    -b "$1" \
    -s one o dn \
    | grep 'dn: OU=' \
    | awk -F= '{ split($2,arr,","); print arr[1] }' 
}

## edit ldap.conf file for allowing ldaps
sudo sed -i.old "s/demand/allow/" /private/etc/openldap/ldap.conf

rb=0 # this ensures that the user goes through the binding process
     # if machine is already bound, and user leaves, they can skip the nonsense

###### User info ######
# Get Username
domainID="$(simpleInput \
    "Please enter your $domain ID before clicking OK." \
    "$domain ID: Binding" \
    "Cancel" \
    "OK")"
if [[ "$?" != 0 ]]; then
    echo "user cancelled"
    exit 0
fi

# Get Password
password="$(hiddenInput \
    "Please enter your $domain password before click OK." \
    "$domain ID: Binding" \
    "Cancel" \
    "OK")"
if [[ "$?" != 0 ]]; then
    echo "user cancelled"
    exit 0
fi

##
###### check if machine is already bound, ask for unbind before continuing
##   
Rebind_Check="$(dsconfigad -show | awk '/Active Directory Domain/{print $NF}')"
# If the domain is correct
if [[ "$Rebind_Check" == "$domainFull" ]]; then
    # Check ID of $aduser
    id -u $adUser
    # If check is successful
    if [[ $? =~ "no such user" ]]; then
        echo "Mac not bound to AD"
    else
        # Force re-binding to AD, -leave or -remove
        # get this info so we can skip all the stuff later
        AD_realName=$(dsconfigad -show | grep "Computer Account" | awk '{print $4}')
        AD_PreviousOU=$(dscl /Search read /Computers/$AD_realName \
            | grep dsAttrTypeNative:distinguishedName \
            | cut -d, -f2- )

        AD_Plist="/Library/Preferences/OpenDirectory/Configurations/Active Directory/"
        Rebind_Full="$(2ButtonInfoBox \
            "This machine is already bound. Re-bind is recommended. 'Leave' will unbind before continuing and preserve the AD record; 'Remove' will unbind and delete the object from AD." \
            "Unbind Machine" \
            "Remove" \
            "Leave")"
            # Chose 'Remove'
            if [[ "$Rebind_Full" =~ "Remove" ]]; then
                echo "$domainID chose to unbind machine, delete object"
                dsconfigad \
                    -remove \
                    -force \
                    -u "${domainID}" \
                    -p "${password}"
                1ButtonInfoBox \
                    "The machine has been removed from AD. Please make sure you add any description or join to any groups needed after rejoining." \
                    "Machine Deleted" \
                    "OK"
                sleep 5
                rm -rf "$AD_Plist"
            # Chose 'Leave'
            elif [[ "$Rebind_Full" =~ "Leave" ]]; then
                echo "$userName chose to unbind machine; keep object"
                dsconfigad \
                    -leave \
                    -localuser "${domainID}" \
                    -localpassword "${password}"
                sleep 15
                rm -rf "$AD_Plist"
                v=2
                rb=1 # skip all the OU selection
            else 
                echo "messed up"
                exit 0
            fi
    fi
else 
    echo "Mac not bound to AD"
fi

#### make sure computer name is correct ######
# only change it if a new bind; existing bind maintain name
if [[ $v -eq 2 ]]; then
1ButtonInfoBox \
    "The computer object still exists in AD. The name is set to $computerName and the machine will re-join its object." \
    "Unbind Complete" \
    "OK"
else    
# ask if user wants to change it
computerName_prompt="$(2ButtonInfoBox \
    "The current name is $computerName. Would you like to change it before continuing?" \
    "Computer Name Change?" \
    "No" \
    "Yes")"
    # Prompt if the user says 'yes' to changing name
    if [[ "$computerName_prompt" =~ "Yes" ]]; then
        $jamfBin policy -event "$rename_trigger"
    fi
fi

$jamfBin policy -event "$forceName_trigger"
computerName="$(scutil --get ComputerName)"

# change HostName and change LocalHostName
sudo scutil --set LocalHostName "$computerName"
sudo scutil --set HostName "$computerName"
echo "set LocalHostName and HostName"

###### name check now done ######

# Which top level OU do you need to go to?
# If we need to add more, add them here
if [[ $rb -eq 0 ]]; then
OUarray=()
for item in $OU_choices
do 
    OUarray+=$"${item}\n"
done
OUarray=$(echo $OUarray |sed 's/..$//')

OU_Choice="$(listChoice \
    "Select a top OU to join" \
    "Select top OU" \
    "Cancel" \
    "OK" \
    $OUarray)"
if [[ "$OU_Choice" =~ "false" ]]; then
    exit 0
fi
DomainC="ou=$OU_Choice,$DomainCSuffix"

n=1
## repeat??

while [[ $n -ne 3 ]]
do
#### Dropdowns for which OU to join to
## OU's under $OU_Choice
while [[ -z $TOP_OUs ]]
do
    IPGET
    TOP_OUs="$(LDAPlookup "$DomainC")"
done

# Ask which main OU you want to join
TOP_OUarray=()
for item in $TOP_OUs
do 
    TOP_OUarray+=$"${item}\n"
done
TOP_OUarray=$(echo $TOP_OUarray |sed 's/..$//')

OU_One="$(listChoice \
    "Select a main OU to join" \
    "Main OU" \
    "Cancel" \
    "OK" \
    $TOP_OUarray )"
if [[ "$OU_One" =~ "false" ]]; then
    exit 0
fi
OU_ONE_FULL="ou=$OU_One,$DomainC"

## OU's under $OU_One 
# curently looks 4 deep. 
# If more are needed, need another if statement
OU_TWO_ALL="$(LDAPlookup "$OU_ONE_FULL")"
OU_TWOarray="$OU_One\n"

for item in $OU_TWO_ALL
    do 
    OU_TWOarray+=$"${item}\n"
done
OU_TWOarray=$(echo $OU_TWOarray | sed 's/..$//')

## Begin mining the depths ############## if 1
if [ -z "$OU_TWO_ALL" ]; then
    OU_JoinFinal="$OU_ONE_FULL"
    echo "$OU_JoinFinal is selection"
    OU_UserGroup="$OU_One"
else
    # Ask which OU (sub $OU_One) you want to join
    OU_Two="$(listChoice \
        "Select a sub OU to join" \
        "AnOUther OU" \
        "Cancel" \
        "OK" \
        $OU_TWOarray)"
    if [[ "$OU_Two" =~ "false" ]]; then
        exit 0
    fi
    OU_TWO_FULL="ou=$OU_Two,ou=$OU_One,$DomainC"
    
    # Check next level
    OU_THREE_ALL="$(LDAPlookup "$OU_TWO_FULL")"
    OU_THREEarray="$OU_Two\n"
    for item in $OU_THREE_ALL
        do 
        OU_THREEarray+=$"${item}\n"
    done
    OU_THREEarray=$(echo $OU_THREEarray | sed 's/..$//')
    # next ############## if 2
    if [ -z "$OU_THREE_ALL" ]; then
        echo "OUs parsed"
        if [[ "$OU_One" == "$OU_Two" ]]; then
            OU_JoinFinal="$OU_ONE_FULL"
            echo "$OU_JoinFinal is selection"
            OU_UserGroup="$OU_One"
        else
            OU_JoinFinal="$OU_TWO_FULL"
            echo "$OU_JoinFinal is selection"
            OU_UserGroup="$OU_Two"
        fi
    else
        # Ask which OU (sub $OU_Two) you want to join    
        OU_Three="$(listChoice \
            "Don't go too deep, you'll awaken the Balrog" \
            "AnOUther OU" \
            "Cancel" \
            "OK" \
            $OU_THREEarray)"
        if [[ "$OU_Three" =~ "false" ]]; then
            exit 0
        fi
        OU_THREE_FULL="ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
        # We have to go deeper ############## if 3
        OU_FOUR_ALL="$(LDAPlookup "$OU_THREE_FULL")"
        OU_FOURarray="$OU_Three\n"
        for item in $OU_FOUR_ALL
            do 
            OU_FOURarray+=$"${item}\n"
        done
        OU_FOURarray=$(echo $OU_FOURarray | sed 's/..$//')
        # how far can we go?
        if [ -z "$OU_FOUR_ALL" ]; then
            echo "OUs parsed"
            if [[ "$OU_Two" == "$OU_Three" ]]; then
                OU_JoinFinal="$OU_TWO_FULL"
                echo "$OU_JoinFinal is selection"
                OU_UserGroup="$OU_Two"
            else
                OU_JoinFinal="$OU_THREE_FULL"
                echo "$OU_JoinFinal is selection"
                OU_UserGroup="$OU_Three"
            fi
        else
            # Ask which OU (sub $OU_Two) you want to join         
            OU_Four="$(listChoice \
                "Drums in the Deep: Khazad Dum" \
                "Durin's Bane" \
                "Cancel" \
                "OK" \
                $OU_FOURarray)"
            if [[ "$OU_Four" =~ "false" ]]; then
                exit 0
            fi
            OU_FOUR_FULL="ou=$OU_Four,ou=$OU_Three,ou=$OU_Two,ou=$OU_One,$DomainC"
        # we're done?
        
        # idk just another check ############## if 4
        OU_FIVE_ALL="$(LDAPlookup "$OU_FOUR_FULL")"
        OU_FIVEarray="$OU_Four\n"
        for item in $OU_FIVE_ALL
            do 
            OU_FIVEarray+=$"${item}\n"
        done
        OU_FIVEarray=$(echo $OU_FIVEarray | sed 's/..$//')
            # how far can we go?
            if [ -z "$OU_FIVE_ALL" ]; then
                echo "OUs parsed"
                if [[ "$OU_Three" == "$OU_Four" ]]; then
                    OU_JoinFinal="$OU_THREE_FULL"
                    echo "$OU_JoinFinal is selection"
                    OU_UserGroup="$OU_Three"
                else
                    OU_JoinFinal="$OU_FOUR_FULL"
                    echo "$OU_JoinFinal is selection"
                    OU_UserGroup="$OU_Four"
                fi
            else
            # Ask which OU (sub $OU_Two) you want to join         
            OU_Five="$(listChoice \
                "I am a servant of the secret fire, wielder of the flame of Anor. You cannot pass. The dark fire will not avail you, flame of Udûn. Go back to the Shadow! You cannot pass." \
                "Final Stand" \
                "Cancel" \
                "OK" \
                "$OU_FIVEarray")"
            if [[ "$OU_Five" =~ "false" ]]; then
                exit 0
            fi
            # MAKE IT STOP ############## if done
                if [[ "$OU_Four" == "$OU_Five" ]]; then
                    OU_JoinFinal="$OU_FOUR_FULL"
                    echo "$OU_JoinFinal is selection"
                    OU_UserGroup="$OU_Four"
                else
                    OU_JoinFinal="$OU_FIVE_FULL"
                    echo "$OU_JoinFinal is selection"
                    OU_UserGroup="$OU_Five"
                fi
            fi
        fi
    fi
fi

# Make $OU_JoinFinal readable
niceOU_Join="$(echo $OU_JoinFinal | sed -e 's/ou=//g;s/,dc=/./g')"

## Make sure this choice is correct
OU_Check="$(2ButtonInfoBox \
    "You are attempting to join $computerName to the following location: $niceOU_Join - is this correct?" \
    "Confirm Selection" \
    "No" \
    "Yes")"
    
if [[ $OU_Check =~ "Yes" ]]; then
    n=3
elif [[ $OU_Check =~ "No" ]]; then
    n=2
    echo "Wrong choice, starting over"
fi
done 

# everything skips if user leaves
elif [[ $rb -eq 1 ]]; then
    OU_JoinFinal=$AD_PreviousOU
    niceOU_Join="$(echo $OU_JoinFinal | sed -e 's/ou=//g;s/,dc=/./g')"
    echo "rebind of machine to $OU_JoinFinal"
    ## Next lines are used for display name and for giving admin rights
    ## adjust as necessary
    ## can ignore if statement if no user groups get admin
    if [[ "$AD_PreviousOU" =~ "$name1" ]]; then
        OU_One=""
        OU_UserGroup=$(echo $AD_PreviousOU \
            | cut -d, -f2- \
            | awk -F, '{print $1}' \
            | awk -F= '{print $2}' )
    elif [[ "$AD_PreviousOU" =~ "$name2" ]]; then
        OU_One=""
    elif [[ "$AD_PreviousOU" =~ "$name3" ]]; then
        OU_One=""
    fi
else 
    echo "something odd"
fi # closes remove/leave option

####### Bind to AD #######
##
## These are also specific to admin groups, adjust as necessary
## Can ignore if no user groups get admin
if [[ "$OU_One" =~ "$name2" ]] || [[ "$OU_One" =~ "$name3" ]]; then
    echo "user group will be $domain\\$admin_here"
    Ask_User="$OU_One"
else
    echo "user group will be $domain\\$admin_here"
    Ask_User="$OU_UserGroup"
fi

userAdmin="$domain\\$admin_here"

# set admin groups
groupAdmin="$domain\\$admin2_here"

# bind to AD
dsconfigad \
    -add "$domainFull" \
    -alldomains disable \
    -computer $computerName \
    -username "${domainID}" \
    -password "${password}" \
    -mobile enable \
    -mobileconfirm disable \
    -ou "$OU_JoinFinal" \
    -passinterval 180 \
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
## 
nameCheck="$(dsconfigad -show | awk '/Computer Account/ {print $NF}')"
adminCheck="$(dsconfigad -show | awk '/admin groups/ {print $NF}')"
domainCheck="$(dsconfigad -show | awk '/Directory Domain/ {print $NF}')"

if [[ -z $nameCheck ]]; then
    1ButtonInfoBox \
        "Something went wrong. Please run the policy again." \
        "Error" \
        "OK"
    # echo output
    echo "Failure to bind. Try again."
else
    1ButtonInfoBox \
        "This computer, ${nameCheck}, has been bound to ${domainCheck}. Groups able to administer are $adminCheck" \
        "Success" \
        "That was easy"
    # echo output
    echo "$nameCheck has been bound to $domainCheck in $niceOU_Join"
fi

# these 2 automatically give 802.1x profile
touch "$wifiJAMFreceipt"
touch "$PEAPProfileReceipt"
$jamfBin recon &
    
exit 0
