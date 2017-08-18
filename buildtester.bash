#!/bin/bash
# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# "buildtester.bash" polls our Jenkins server (http://jenkins.currant.com:8080)
# periodically to check for new builds. When a new build is found, the script
# downloads the build and performs an over-the-air update onto test hardware,
# then runs some simple tests to establish the viability of the build.
#
# The script logs events of interest to file "buildtester.log".


# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# help() emits a bunch of (hopefully useful) information

help() 
{
	cat <<EOF

"`basename $0`" polls our Jenkins build server several times a minute,
looking for builds to test. When a new build appears this script downloads
it and proceeds to test it by attempting the following operations:

    1.) Using ziggy, the script attempts an over-the-air (via attached
        bluetooth dongle) update with the new build.

    2.) If the OTA update succeeds, the script uses ble-console to read the
        version number of the firmware now running on the outlet and
        compares this to the name of the file containing the new image
        downloaded from the Jenkins server. Both contain a git commit sha,
        and if the shas match this tests succeeds.

    3.) The script then attempts to configure the outlet using the command:

        ziggy --prod client setup

    4.) If the script manages to configure the outlet, it then attempts to
        de-configure it using this ziggy invocation:

        ziggy --prod client clear

Each test relies on the success of the previous test. A given build
"passes" only if it successfully completes all four tests. The tests aren't
perfect: because they rely on a USB/BLE dongle to communicate with the
outlet, a test may fail through no fault of the build itself but rather
because these dongles don't always manage to connect on the first
attempt. As a result each test is designed to retry up to five times should
it fail due to a communications problem with the dongle. 

Retrying is not a perfect solution - there is always a chance that the
dongle will foul up five times in a row. But as the script runs it compiles
a log in the local file "buildtester.log" - the operator can should be able
to catch "false failures" of this kind by examining the log.


EOF
}

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# Check and see if the user wants to see some help -
# the presence of any arguments to the shell script
# triggers the display of the help message:

if [ ! -z $1 ]
then
	help
	exit 0
fi


# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# First load the "library" scripts containing the functions
# that the high-level calls in this script rely on. Note
# that order is important: source the "jenkins_lib.bash"
# before you source the "tests_lib.bash" script.

source ./jenkins_lib.bash
source ./tests_lib.bash

# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# Before entering the main loop, call "preflight()" which
# checks to make sure that all the requirements needed
# to allow this script to run are satisfied - requirements
# such as: Is there already an instance of "buildtester"
# running? Is a BLE/USB dongle present? Is the script able
# to log into the Currant backend? (a pre-requisite for
# configuring and de-configuring the outlet). And so on.
# "preflight()" will exit if any issues are encountered
# so there's no need to test the return vaule:

preflight


# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
# The main loop. "buildtester.bash" is designed to run
# "forever" (either in the background or the foreground),
# polling the Jenkins server for fresh builds:
while [ 1 ]
do

	get_latest_build_number
	if [ ! -d $LATESTBUILD ]
	then
		get_latest_build
		if [ $? -eq 0 ]
		then
			echo "0" > .$LATESTBUILD
			while [ 1 ]
			do
				test_latest_build $LATESTBUILD
				if [ $? -eq 0 ]
				then
					break
				else
					log "test_latest_build() failed to run all tests against Jenkins Build Number $LATESTBUILD - will pause and try again."
					sleep $POLLING_INTERVAL
				fi
			done
			log "test_latest_build() succeeded in running all tests against Jenkins Build Number $LATESTBUILD"
		else
			log "Failed to download build number $LATESTBUILD and so aborting tests"
		fi
	else
	    log "We've already downloaded Jenkins Build Number $LATESTBUILD - so test it directly"
	    test_latest_build $LATESTBUILD
	fi

	sleep $POLLING_INTERVAL

	 

done
