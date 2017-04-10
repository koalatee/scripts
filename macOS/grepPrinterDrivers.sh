#!/bin/sh
# easily get all printers installed on the machine and their drivers

# Logged in user
USERNAME=$(python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')

# output file | change as desired
# Filename on /Users/$USERNAME/Desktop
filename=printerdriverinfo.csv
Output="/Users/$USERNAME/Desktop/$filename"

# Create output file with following parameters
if [[ ! -f "$Output" ]]; then
echo "Printer Name, Printer Model, Printer Driver, Printer IP" > "$Output"
fi

# list all printers by name
allPrinters=($(lpstat -a | sed 's/ accepting.*//g'))

# get info for each printer
for eachprinter in "${allPrinters[@]}"
do
# get printer --make-and-model
    printermodel=$(echo `lpoptions -p $eachprinter` | sed 's/.*printer-make-and-model=//' | sed 's/ printer-state.*//' | sed 's/,.*//' | tr -d \' )
# get printer ip
    printerip=$(echo `lpoptions -p $eachprinter` | sed 's/.*socket://' | sed 's/finishings.*//' | tr -d //)
# get printer driver
    printerDriverShort=$(echo `lpinfo --make-and-model "$printermodel" -m` | awk -F"/" '{print $6}' | sed 's/\.gz.*/.gz/')
        echo "PRINTER INFORMATION"
        echo "Printer Name: $eachprinter"
        echo "Printer Model: $printermodel" 
        echo "Printer Driver: $printerDriverShort"
        echo "Printer IP: $printerip"
        echo ""
# output to file
   echo "$eachprinter,$printermodel,$printerDriverShort,$printerip" >> "$Output"
done

exit 0
