#!/bin/bash

## jjourney 11/2017
## This is a check to get Office applications up to date
## Checks to see if any apps are running
## If none running, run whole suite installer
## If any apps are running, run each policy individually
## Temporary solution until MAU4 is production release

#### jamf variables
# full installer variables
fulltriggercache="polOfficeUpdateScriptCache"
fulltriggerinstall="polOfficeUpdateScriptInstall"

# individual installer variables
exceltriggerinstall="polExcelInstall"
wordtriggerinstall="polWordInstall"
ppttriggerinstall="polPPTInstall"
onenotetriggerinstall="polOneNoteInstall"
outlooktriggerinstall="polOutlookInstall"
mautriggerinstall="polMAUInstall"

# set in script parameters in jamf
currentVerAll="$4"
currentVerMAU="$5"

# local parameters
jamfBin="/usr/local/jamf/bin/jamf"
Waiting_Room="/Library/Application Support/JAMF/Waiting Room/"
OfficePKG="Office2016-$currentVerAll.pkg"
OfficePKGXML="Office2016-$currentVerAll.pkg.cache.xml"

# Set here for not up to date, change later if up to date
OfficeAll=0 # 0 = up to date | 1 = some out of date
OfficeExc=0 # 0 = up to date | 1 = out of date
OfficeWor=0 # 0 = up to date | 1 = out of date
OfficePPT=0 # 0 = up to date | 1 = out of date
OfficeOut=0 # 0 = up to date | 1 = out of date
OfficeOne=0 # 0 = up to date | 1 = out of date
OfficeMAU=0 # 0 = up to date | 1 = out of date
OfficeRunning=0 # 0 = none running | 1 = some running

#### Check Disk Space Function
function DiskSpaceCheck() {
    diskSpace=$(df -miH / |grep /dev/ |awk '{print $4}' |sed 's/G//')
    if [[ $diskSpace -lt 10 ]]; then
        echo "most likely, not enough disk space. Exiting"
        exit 1
    fi
}

#### Check Office Versions Function
function OfficeVersionCheck() {
    ExcelVer=$(/usr/bin/defaults read "/Applications/Microsoft Excel.app/Contents/Info.plist" CFBundleShortVersionString)
    WordVer=$(/usr/bin/defaults read "/Applications/Microsoft Word.app/Contents/Info.plist" CFBundleShortVersionString)
    PowerPointVer=$(/usr/bin/defaults read "/Applications/Microsoft PowerPoint.app/Contents/Info.plist" CFBundleShortVersionString)
    OneNoteVer=$(/usr/bin/defaults read "/Applications/Microsoft OneNote.app/Contents/Info.plist" CFBundleShortVersionString)
    OutlookVer=$(/usr/bin/defaults read "/Applications/Microsoft Outlook.app/Contents/Info.plist" CFBundleShortVersionString)
    MAUVer=$(/usr/bin/defaults read "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/Info.plist" CFBundleShortVersionString)

    ## Check versions of apps
    st=0
    for i in $ExcelVer $WordVer $PowerPointVer $OneNoteVer $OutlookVer; do
        [ "$currentVerAll" = "$i" ]
        st=$(( $? + st ))
    done

    ## help, this next section sucks
        if [[ $ExcelVer != $currentVerAll ]]; then
            OfficeExc=1
        fi
        if [[ $WordVer != $currentVerAll ]]; then
            OfficeWor=1
        fi
        if [[ $PowerPointVer != $currentVerAll ]]; then
            OfficePPT=1
        fi
        if [[ $oneNoteVer != $currentVerAll ]]; then
            OfficeOne=1
        fi
        if [[ $OutlookVer != $currentVerAll ]]; then
            OfficeOut=1
        fi

    ## $st will not equal 0 if one is out of date
    if [ $st -eq 0 ]; then
        echo "All up to date"
    else 
        echo "Some out of date"
        OfficeAll=1
    fi

    ## Check MAU version
    if [ "$MAUVer" = "$currentVerMAU" ]; then
        echo "MAU up to date"
    else
        echo "MAU not up to date"
        OfficeMAU=1
    fi
}

#### Check If Apps Are Running Function
function OfficeRunningCheck() {
    # Reset counter
    OfficeRunning=0
    ## this should call individual functions to check for each version
    ## should check pbowden's github / office removal scripts
    ExcelRunning=$(ps axc |awk '/Microsoft Excel/{print $1}')
    WordRunning=$(ps axc |awk '/Microsoft Word/{print $1}')
    PowerPointRunning=$(ps axc |awk '/Microsoft PowerPoint/{print $1}')
    OneNoteRunning=$(ps axc |awk '/Microsoft OneNote/{print $1}')
    OutlookRunning=$(ps axc |awk '/Microsoft Outlook/{print $1}')
    MAURunning=$(ps axc |awk '/Microsoft AU Daemon/{print $1}')

    ps=0
    for i in $ExcelRunning $WordRunning $PowerPointRunning $OneNoteRunning $OutlookRunning; do
        if [ -z "$i" ]; then
            echo "$i not running"
        else
            ps=$(( $? + ps )) 
        fi
    done
    if [ $ps -ne 0 ]; then
        OfficeRunning=1
    fi
}

#### Check
function RunOfficeFullInstaller() {

    OfficeRunningCheck
    if [ $OfficeRunning -eq 0 ]; then
        ## If not, make sure there is enough free space
        echo "No Office apps running, proceeding to DiskSpaceCheck."
        DiskSpaceCheck

        # Run policy to cache
        echo "Caching Office v $currentVerAll"
        $jamfBin policy -event $fulltriggercache
        echo "Office $currentVerAll cached successfully."

        # Check to make sure they are still not running
        OfficeRunningCheck

        if [ $OfficeRunning -eq 1 ]; then
            echo "After caching, an Office App was opened. Removing cached content."
            rm -rf "$Waiting_Room""$OfficePKG"
            rm -rf "$Waiting_Room""$OfficePKGXML"
            echo "Will try individual apps now"
        else
            echo "Office Apps still not running, continuing"
            # If not, run policy to install from cache
            $jamfBin policy -event $fulltriggerinstall
            echo "Office Install Completed."
            exit 0
        fi
    fi
}

#### If some are running or if some are up to date, go through each one
function RunOfficeIndividualInstaller() {
    # Check if each is running
    OfficeRunningCheck
    DiskSpaceCheck

    if [ -z $ExcelRunning ]; then
        if [ $OfficeExc -eq 1 ]; then
            echo "Excel not running, out of date"
            $jamfBin policy -event $exceltriggerinstall
            echo "updated Excel to $currentVerAll"
        else
            echo "Excel running, up to date"
        fi
    else   
        echo "Excel running, run later"
    fi

    OfficeRunningCheck
    DiskSpaceCheck
    if [ -z $WordRunning ]; then
        if [ $OfficeWor -eq 1 ]; then
            echo "Word not running, out of date"
            $jamfBin policy -event $wordtriggerinstall
            echo "updated Word to $currentVerAll"
        else
            echo "Word running, up to date"
        fi
    else   
        echo "Word running, run later"
    fi
    OfficeRunningCheck
    DiskSpaceCheck
    if [ -z $PowerPointRunning ]; then
        if [ $OfficePPT -eq 1 ]; then
            echo "PowerPoint not running, out of date"
            $jamfBin policy -event $ppttriggerinstall
            echo "updated PowerPoint to $currentVerAll"
        else
            echo "PowerPoint running, up to date"
        fi
    else   
        echo "PowerPoint running, run later"
    fi
    OfficeRunningCheck
    DiskSpaceCheck
    if [ -z $OneNoteRunning ]; then
        if [ $OfficeOne -eq 1 ]; then
            echo "OneNote not running, out of date"
            $jamfBin policy -event $onenotetriggerinstall
            echo "updated OneNote to $currentVerAll"
        else
            echo "OneNote running, up to date"
        fi
    else   
        echo "OneNote running, run later"
    fi
    OfficeRunningCheck
    DiskSpaceCheck
    if [ -z $OutlookRunning ]; then
        if [ $OfficeOut -eq 1 ]; then
            echo "Outlook not running, out of date"
            $jamfBin policy -event $outlooktriggerinstall
            echo "updated Outlook to $currentVerAll"
        else
            echo "Outlook running, up to date"
        fi
    else   
        echo "Outlook running, run later"
    fi
    OfficeRunningCheck
    DiskSpaceCheck  
    if [ -z $MAURunning ]; then  
        if [ $OfficeMAU -eq 1 ]; then
            echo "MAU not running, out of date"
            $jamfBin policy -event $mautriggerinstall
            echo "updated MAU to $currentVerMAU"
        else   
            echo "MAU running, up to date"
        fi
    else
        echo "MAU running, run later"
    fi

    echo "All individual apps processed. Exiting"
}

## Run everything
OfficeVersionCheck
RunOfficeFullInstaller
RunOfficeIndividualInstaller
