#!/bin/bash
# put all computer names in the department groups and output to single .csv on /Users/$loggedInUser/Desktop
# puts total number of machines in each dept
# Sorted by Department

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
Output="/Users/$loggedInUser/Desktop/department+computers.csv"

# JSS
jss="https://your.jss.here:8443"
CD2_trigger="polCocoaDialog"

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
####### Get all computer data
api_AllComputersRaw="$(curl \
        -s \
        -v \
        -u ${username}:${password} \
        -X GET $jss/JSSResource/computers/subset/basic \
        -H "Accept: application/xml" \
        )"
    
# Total number of managed machines to route through
api_ComputerTotal="$(curl \
    -s \
    -v \
    -u ${username}:${password} \
    -X GET $jss/JSSResource/computergroups/id/1 \
    -H "Accept: application/xml" \
    |xpath //computer_group/computers/size \
    | sed -e 's/<size>//;s/<\/size>//' \
    )"
    
# All machines in array
api_AllComputerNames="$(echo $api_AllComputersRaw \
        |xpath "/computers/computer[managed = 'true']/name" \
        |sed -e 's/ /_/g' \
        |sed -e 's/<name>//g;s/<\/name>/ /g' \
        )"
comp_allArray=($api_AllComputerNames)

## Get all departments 
api_AllDeptRaw="$(curl \
        -s \
        -v \
        -u ${username}:${password} \
        -X GET $jss/JSSResource/departments \
        -H "Accept:application/xml" \
        )"
 
# Find highest number in array 
dept_Numbers="$(echo $api_AllDeptRaw \
        |xpath "/departments/department/id" \
        |sed -e 's/<id>//g;s/<\/id>/ /g' \
        )"
dept_NumberArray=($dept_Numbers)   

# total number of machines (for error checking) 
Machine_count=0

# Set column names
echo "JSS ID,DEPARTMENT NAME,TOTAL MACHINES,MACHINES IN DEPARTMENT" >> "$Output"

# Create arrays for all departments
for d in ${dept_NumberArray[@]}
do
    # Get next dept in line
    dept_Individual="$(echo $api_AllDeptRaw \
            | xpath "/departments/department[id = '$d']/name" \
            | sed -e 's/<name>//g;s/<\/name>//g' \
            )"      
           
        # Get managed computers that match the dept
        echo "checking machines in the department: $dept_Individual"
        
        ## Declare variable each go round
        declare -a "computer_array"
        computer_array=()
        Computer="placeholder"
        
        #c=1
        #while [[ "$Computer" != "None found" ]]
        #do
            ## Get every computer in the array
            name_Computer="$(echo $api_AllComputersRaw \
                |xpath "/computers/computer[department = '$dept_Individual'][managed = 'true']/name" \
                |sed -e 's/ /_/g' \
                |sed -e 's/<name>//g;s/<\/name>/ /g' \
                )" 
            
            ## Rules for ending when finished
            # First is if the dept has no macs
            if [[ -z "$name_Computer" ]]; then
                computer_array=("No Macs found in this department")
                Computer="None found"
            else 
                computer_array+=($name_Computer)
                big_array+=($name_Computer)
            fi
            
        if [[ "${computer_array[@]}" =~ "No Macs found" ]]; then
            number_Computer=0
        else
            number_Computer=${#computer_array[@]}
        fi
        # on to the next
        #c=$(($c+1))
        #done
    
    # Add to total number of machines 
    Machine_count=$(($Machine_count + $number_Computer))
    
    ## Output to file
    echo "$d,$dept_Individual,$number_Computer,${computer_array[@]}" >> "$Output"
    
    
done

## Blank machines
echo "checking machines with blank departments"
# Variables
Computer="placeholder"
declare -a "computer_array"
computer_array=()
c=1
while [[ "$Computer" != "None found" ]]
do
    # Get every computer in the array
    name_Computer="$(echo $api_AllComputersRaw \
        |xpath "/computers/computer[department = ''][managed = 'true'][$c]/name" \
        |sed -e 's/<name>//g;s/<\/name>/ /g' \
        )" 
    comp_arrayEdit="$(echo $name_Computer \
        |sed -e 's/ /_/g' \
        )"
        
        if [[ $c -gt 1 ]] && [[ -z "$name_Computer" ]]; then
            number_Computer=${#computer_array[@]}
            Computer="None found"
        else 
            computer_array+=("$name_Computer")
            big_array+=("$comp_arrayEdit")
        fi
    
c=$(($c+1))
done
number_Computer=${#computer_array[@]}
Machine_count=$(($Machine_count + $number_Computer))

## Output
echo ",No department,$number_Computer,${computer_array[@]}" >> "$Output"

## Totals
echo ",Total managed machines in JSS,$api_ComputerTotal" >> "$Output"
echo ",Total number of machines counted,$Machine_count" >> "$Output"

for i in ${comp_allArray[@]}
do
    if [[ "${big_array[@]}" =~ "$i" ]]; then
        echo "$i is in both"
    else
        echo ",$i not sorted" >> "$Output"
    fi
done

exit 0
