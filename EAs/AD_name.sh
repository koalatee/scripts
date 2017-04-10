#!/bin/bash
# taken from https://jamfnation.jamfsoftware.com/discussion.html?id=10325

adName=$(dsconfigad -show | grep "Computer Account" | awk '{print toupper}' | awk '{print $4}' | sed 's/$$//')

if [ ! "$adName" ]; then
adName="Not Bound"
fi

echo "<result>$adName</result>"
