#!/bin/sh

profiles=$(profiles -C -v | awk -F: '/attribute: name/{print $NF}' | sort)
echo "<result> $profiles </result>"

exit 0
