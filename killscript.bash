#!/bin/bash

readonly LOGFILE=buildtester.log
readonly LOCKFILE=/tmp/buildtester-lockfile

SCRIPTNAME="buildtester.bas"

PROCESSID=`ps -e | grep $SCRIPTNAME | grep -v grep | grep $SCRIPTNAME | sed 's/\([0-9]\) .*/\1/'`

if [ -z $PROCESSID ]
then
	echo "buildtester.bash is not running"
else
	echo "Killing $PROCESSID"
	kill -9 $PROCESSID

	# Log what happened:
	log_timestamp=`date`
	echo -n "$log_timestamp" >> $LOGFILE

	echo -n " (PID=" >> $LOGFILE
	echo -n "$PROCESSID)" >> $LOGFILE

	echo -n -e ":\t" >> $LOGFILE
	echo "Somebody just killed me." >> $LOGFILE

	# Remove the lock directory
	rmdir $LOCKFILE

fi




