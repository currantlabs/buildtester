#!/bin/bash

# "buildtester.bash" polls our Jenkins server (http://jenkins.currant.com:8080)
# periodically to check for new builds. When a new build is found, the script
# downloads the build and performs an over-the-air update onto test hardware,
# then runs some simple tests to establish the viability of the build.
#
# The script logs events of interest to file "buildtester.log".
readonly LOGFILE=buildtester.log


# "POLLING_INTERVAL" defines how often (in units of seconds) the script checks
# for new Jenkins builds:
readonly POLLING_INTERVAL=10

	



# "LATESTBUILD" holds the latest build number as reported by our Jenkins server.
# Initialized to 0 for error checking purposes:
LATESTBUILD=0

# define a bunch of error codes (E_SUCCESS means "success" but
# this script is never supposed to return):
readonly E_SUCCESS=0
readonly E_JENKINSACCESSFAILED=1
readonly E_ANOTHERINSTANCEAPPEARSTOBERUNNING=2
readonly E_JENKINSPOLLUTILITYNOTFOUND=3
readonly E_CANNOTIDENTIFYPLATFORM=4
readonly E_WGETNOTAVAILABLE=5

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# We use a lockfile to prevent multiple instances of this script
# from running at the same time - so it's important that we
# use TRAP to ensure that some cleanup happens before the script
# exits:

trap cleanup EXIT SIGHUP SIGINT SIGTERM

# Here's the lockfile (actually a directory):
LOCKFILE=/tmp/buildtester-lockfile

# On exit, you normally want to delete the lockfile - the
# exception to this rule is when you abort the script
# because you've determined that another instance is already
# running (using the "test_lockfile()" function).
# KEEPLOCKFILE exists so that it can be set to '1' in
# the case that you exit the script due to detection
# of another running instance.

KEEPLOCKFILE=0

# Here's the function used to "test the lock" that gets run
# each time we start this script:
function test_lockfile()
{
	if [ -e  $LOCKFILE  ]
	then
		log "Another instance of $0 appears to be running - bailing."
		echo "Another instance of $0 appears to be running - bailing."
		KEEPLOCKFILE=1
		exit $E_ANOTHERINSTANCEAPPEARSTOBERUNNING
	fi

	mkdir $LOCKFILE 

}

function cleanup()
{
	if [ $KEEPLOCKFILE -eq 0 ]
	then
		if [ -e $LOCKFILE ]
		then
			rmdir $LOCKFILE
		fi
	fi
	exit
}

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# log() appends a log entry with timestamp and PID to the LOGFILE
function log()
{
	local log_entry log_timestamp

	log_timestamp=`date`
	echo -n "$log_timestamp" >> $LOGFILE

	echo -n " (PID=" >> $LOGFILE
	echo -n "$$)" >> $LOGFILE

	echo -n -e ":\t" >> $LOGFILE
	echo "$1" >> $LOGFILE
	
}

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 

# get_latest_build_number() contacts the Jenkins server
# (by invoking the "jenkinspoll.go" Go program), aborts
# the script if any errors occur. Otherwise updates the
# LATESTBUILD variable.
function get_latest_build_number()
{

	if [ ! -e $JENKINSPOLLER ]
	then
		log "The executable $JENKINSPOLLER could not be found - bailing."
		exit $E_JENKINSPOLLUTILITYNOTFOUND
	fi

	$JENKINSPOLLER

	LATESTBUILD=$?

	if [ $LATESTBUILD -le 0 ]
	then
		log "Failed to access the Jenkins server - error code returned by the $JENKINSPOLLER was $LATESBUILD."
		exit $E_JENKINSACCESSFAILED
	fi
}

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 

function getapp()
{
	log "Getting the proposition app for Build Number: $1"
	wget -q -r -l3 -np http://jenkins.currant.com/images/ -P $1 -A "app$1*.img.gz"

}

function getbl()
{
	log "Getting the booloader for for Build Number: $1"
	wget -q -r -l3 -np http://jenkins.currant.com/images/ -P $1 -A "bl$1*.img.gz"

}

function get_latest_build()
{

	log "Downloading Build number $LATESTBUILD"

	mkdir $LATESTBUILD

	getapp $LATESTBUILD

	getbl $LATESTBUILD

}

