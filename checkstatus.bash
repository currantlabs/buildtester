#!/bin/bash

# "checkstatus.bash" is just a quick way to check and see if the
# buildtester.bash script (the script that periodically checks to
# see if Jenkins has a new build for us to test) is running or not.

SCRIPTNAME="buildtester.bas"
SCRIPTFULLNAME="buildtester.bash"


ps | grep $SCRIPTNAME | grep -v grep | grep $SCRIPTNAME > /dev/null
if [ $? -eq 0 ]; then echo "Yes, an instance of $SCRIPTFULLNAME is running."; else echo "No, $SCRIPTFULLNAME is not currently running."; fi
