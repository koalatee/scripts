#!/bin/sh

OSMajorVersion=$(sw_vers -productVersion | cut -d '.' -f 1,2)

if [[ "$OSMajorVersion" == "10.11" || "$OSMajorVersion" == "10.12" ]] ; then
    echo "<result>`csrutil status | awk '{ print $5; exit }' | sed 's/.$//'`</result>"
else
    echo "<result>SIP not applicable</result>"
fi
