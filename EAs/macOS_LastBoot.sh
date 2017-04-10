#!/bin/sh

lastBootRaw=$(sysctl kern.boottime | awk -F'[= |,]' '{print $6}')
lastBootFormat=$(date -jf "%s" "$lastBootRaw" +"%Y-%m-%d %T")

echo "<result>$lastBootFormat</result>"
