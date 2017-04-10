#!/bin/sh

## Uptime expressed as hours in floating point notation

## Get uptime in seconds from sysctl
secUp=$( sysctl kern.boottime | awk -F'[= |,]' '{print $6}' )

## Get Unix time in seconds
epochTime=$( date +%s )

## Calculate adjusted uptime for computer
adjTime=$( echo "$epochTime" - "$secUp" | bc )

## Calculate uptime in hours in 'hundredths' decimal notation
HrsUp=$( echo "scale=2;$adjTime / 3600" | bc )

echo "<result>$HrsUp</result>"
