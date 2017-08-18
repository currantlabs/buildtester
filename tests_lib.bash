#!/bin/bash

MACADDR=""
MACADDRCONFIGURED=""
MACADDRDECONFIGURED=""
LOCATIONID=""
LOGINID=""
LOGINPASSWD=""

MACADDRCONFIGURED=`cat macaddr-configured.txt`
MACADDRDECONFIGURED=`cat macaddr-deconfigured.txt`
LOGINID=`cat login-id.txt`
LOGINPASSWD=`cat login-passwd.txt`
LOCATIONID=`cat location-id.txt`

MACADDRSCANRESULTS="/tmp/macaddrs"
SETUPRESULTS="/tmp/setup"
CLEARRESULTS="/tmp/clear"
RETRIES=5
FWBURNTIME=30

# At startup, there are some things you need to do:
# (1) find the firmware image (i.e., the app)
# (2) remove the MACADDRSCANRESULTS file so you force a refresh
# (3) log-in to the backend so that you can run all of the tests

rm -f $MACADDRSCANRESULTS

if [ -z $LOGINPASSWD ]
then
    echo "You must save your backend login password to \"login-passwd.txt\" in order to use this test script."
    return 7
fi

if [ -z $LOGINID ]
then
    echo "You must save your backend login password to \"login-id.txt\" in order to use this test script."
    return 7
fi


sudo LOGXI=* ./ziggy --prod login $LOGINID $LOGINPASSWD


reset_ble()
{
	log "reset_ble() call has been disabled"

    # log "reset_ble(): Before reset of device \"sudo hcitool dev\" says:"
    # echo "-------- -------- -------- --------" >> $LOGFILE
    # sudo hcitool dev >> $LOGFILE
    # echo "-------- -------- -------- --------" >> $LOGFILE

    # sudo hciconfig hci0 reset

	# sudo hciconfig hci0 down

    # log "reset_ble(): After \"sudo hciconfig hci0 down\", running \"sudo hciconfig\" says:"
    # echo "-------- -------- -------- --------" >> $LOGFILE
    # sudo hciconfig >> $LOGFILE
    # echo "-------- -------- -------- --------" >> $LOGFILE

    # log "reset_ble(): After reset of device \"sudo hcitool dev\" says:"
    # echo "-------- -------- -------- --------" >> $LOGFILE
    # sudo hcitool dev >> $LOGFILE
    # echo "-------- -------- -------- --------" >> $LOGFILE

}

ota_test()
{
    attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

		log "Attempting to upgrade the device with MAC address $MACADDR"
		log "Upgrading to application [$FWIMAGE]"

        sudo ./ziggy client upgrade  --application=$FWIMAGE --install=true $MACADDR > /dev/null 2> /dev/null

        if [ $? -ne 0 ]
        then
            log "ota_test(): OTA update failed on attempt $attempts/$RETRIES."
            if [ $attempts -eq $RETRIES ]
            then
                break
            else
                reset_ble
                sleep 2
            fi
        else
            log "ota_test(): OTA update succeeded on attempt $attempts/$RETRIES."
            break
        fi

    done

    if [ $attempts -eq $RETRIES ]
    then
        return 1 
    fi

    # Takes about 15 seconds for the outlet to complete FW update
    # once the data has been sent OTA, so give the outlet a chance
    # to finish before checking the result:
    # echo "Waiting for hardware to flash the new application image..."
    sleep $FWBURNTIME

    return 0
}

version_test()
{
    local RESULTFILE=/tmp/version
    local GITSHA=`echo $FWIMAGE | sed 's/^.*-\([a-z0-9]*\)\\.img\\.gz.*$/\1/'`
    log "version_test(): Testing the new application image for $GITSHA"

    attempts=0

    local lines

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo ./ble-console -addr $MACADDR -command version | tee $RESULTFILE > /dev/null 

        OUTPUTSIZE=`stat --format="%s" $RESULTFILE`

        if [ $OUTPUTSIZE -eq 0 ]
        then
            log "version_test(): Attempt to gather FW version information failed on attempt $attempts/$RETRIES."
            if [ $attempts -eq $RETRIES ]
            then
                break
            else
                reset_ble
                sleep 2
                continue
            fi
        fi

        lines=`cat $RESULTFILE | wc -l`
        if [ $lines -lt 10 ]
        then
            log "version_test(): Only captured $lines lines of data - looks like a BT communications problem. Trying again..."
            echo "-------- -------- -------- --------"  >> $LOGFILE
            cat $RESULTFILE  >> $LOGFILE
            echo "-------- -------- -------- --------"  >> $LOGFILE
            reset_ble
            sleep 2
            continue
        fi
        


        log "version_test(): Attempt to collect FW version data succeeded on attempt $attempts."
        echo "-------- -------- -------- --------"  >> $LOGFILE
        cat $RESULTFILE  >> $LOGFILE
        echo "-------- -------- -------- --------"  >> $LOGFILE

        break


    done

    if [ $attempts -eq $RETRIES ]
    then
        return 2
    fi

    # Check and see if the version number is consistent:
    grep "App version String" $RESULTFILE | grep -q $GITSHA

    if [ $? -ne 0 ]
    then
        log "Failed to match target $GITSHA in the following captured version data:"
        echo "----------------------------------------------------------------" >> $LOGFILE
        cat $RESULTFILE >> $LOGFILE
        echo "----------------------------------------------------------------" >> $LOGFILE
        return 1
    fi

    # echo "Version string matches"
    return 0
}

configure_test()
{
    local attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo LOGXI=* ./ziggy --prod client setup --lid="$LOCATIONID" $MACADDRDECONFIGURED > $SETUPRESULTS

        grep -q "client error connecting" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            log "configure_test(): Got \"client error connecting\" - re-setting BLE and trying again."
            reset_ble
            sleep 2
            continue
        fi

        grep -q "no devices available" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            log "configure_test(): Got \"no devices available\" - aborting test (return code is 2)."
            return 2
        fi

        grep -q "client could not find device mac" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            log "configure_test(): Got \"client could not find device mac\" - aborting test (return code is 3)."
            return 3
        fi


        grep -q "client device successfully configured" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            # The MAC address has changed so reset the MAC address scan results file
            log "configure_test(): Success! Got \"client device successfully configured\" - returning 0 to indicate test passed."
            rm -f $MACADDRSCANRESULTS
            MACADDR=""
            return 0
        fi


    done

    return 1

    
}

setup()
{
    configure_test

    if [ $? -eq 0 ]
    then
        echo "configure_test succeeded"
    else
        echo "configure_test failed"
        exit 1
    fi
}

deconfigure_test()
{
    local attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo ./ziggy --prod client clear $MACADDRCONFIGURED > $CLEARRESULTS

        grep -q "client error connecting" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            log "deconfigure_test(): Got \"client error connecting\" - re-setting BLE and trying again."
            reset_ble
            sleep 2
            continue
        fi

        grep -q "no devices available" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            log "deconfigure_test(): Got \"no devices available\" - aborting test (return code is 2)."
            return 2
        fi

        grep -q "client could not find device mac" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            log "deconfigure_test(): Got \"client could not find device mac\" - aborting test (return code is 3)."
            return 3
        fi

        grep -q "client device successfully deconfigured" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            # The MAC address has changed so reset the MAC address scan results file
            log "deconfigure_test(): Success! Got \"client device successfully configured\" - returning 0 to indicate test passed."
            rm -f $MACADDRSCANRESULTS
            MACADDR=""
            return 0
        fi


    done

    return 1

    
}

clear()
{
    deconfigure_test

    if [ $? -eq 0 ]
    then
        echo "deconfigure_test succeeded"
    else
        echo "deconfigure_test failed"
        exit 1
    fi
    
}

ota()
{
    ota_test

    if [ $? -eq 0 ]
    then
        echo "ota_test succeeded"
    else
        echo "ota_test failed"
        exit 1
    fi
}

version()
{
    version_test

    if [ $? -eq 0 ]
    then
        echo "version_test succeeded"
    else
        echo "version_test failed"
        exit 1
    fi
}

scanmacaddrs()
{
    local attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo ./ziggy --prod client scan > /tmp/macaddrs

        grep -q "connection timed out" $MACADDRSCANRESULTS
        if [ $? -eq 0 ]
        then
            sleep 2
            continue
        fi

        grep -q "no devices available" $MACADDRSCANRESULTS
        if [ $? -eq 0 ]
        then
            return 2
        fi

        grep -q "client scan got discovery" $MACADDRSCANRESULTS
        if [ $? -eq 0 ]
        then
            return 0
        fi

    done

    return 1

}

findmac()
{
    if [ ! -e $MACADDRSCANRESULTS ]
    then
        echo "Must scan for MAC addresses before you can determine the device's current MAC address."
        return 1
    fi

    grep -q "$MACADDRCONFIGURED" $MACADDRSCANRESULTS
    if [ $? -eq 0 ]
    then
        MACADDR=$MACADDRCONFIGURED
        return 0
    fi

    grep -q "$MACADDRDECONFIGURED" $MACADDRSCANRESULTS 
    if [ $? -eq 0 ]
    then
        MACADDR=$MACADDRDECONFIGURED
        return 0
    fi

    return 1
    
}

isconfigured()
{
    if [ ! -e $MACADDRSCANRESULTS ] 
    then
        echo "You have to scan for MAC addresses before you can determine whether the device is configured or not."
        return 2
    fi

    if [ -z $MACADDR ]
    then
        echo "Have not determined the MAC address"
        return 1
    fi

    if [ -z $MACADDRCONFIGURED ]
    then
        echo "Have not setup the expected configured MAC address yet (should be in the file macaddr-configured.txt)."
        return 2
    fi

    if [ -z $MACADDRDECONFIGURED ]
    then
        echo "Have not setup the expected deconfigured MAC address yet (should be in the file macaddr-deconfigured.txt)."
        return 3
    fi

    if [ "$MACADDR" == "$MACADDRCONFIGURED" ]
    then
        echo "The outlet has been configured."
        return 0
    elif [ "$MACADDR" == "$MACADDRDECONFIGURED" ]
    then
        echo "The outlet is not configured."
        return 0
    else
        echo "MAC addr $MACADDR matches neither the configured MAC address ($MACADDRCONFIGURED) nor the deconfigured MAC address ($MACADDRDECONFIGURED) - wtf?"
        return 4
    fi




}

mac()
{
    if [ -z $MACADDR ]
    then
        echo "Have not determined the MAC address"
    else
        echo "The MAC address is $MACADDR"
    fi

}


preflight()
{


    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
    # Get something in the log to show a new instance was run:
    log "$0 starting up..."


    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
    # The code that actually polls the Jenkins server is a compiled Go program,
    # and there is a Mac OS and Linux version -- pick the right one:

    PLATFORM=`uname`
    if [[ $PLATFORM == "Darwin" ]]
    then
        JENKINSPOLLER=./jenkinspoll
    elif [[ $PLATFORM == "Linux" ]]
    then
        JENKINSPOLLER=./jenkinspoll_linux
    else
        echo "Can't identify the OS we're running under -- bailing."
        exit $E_CANNOTIDENTIFYPLATFORM
    fi

    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
    # test_lockfile() checks to make sure there isn't another
    # instance of the "buildtester.bash" script running already;
    # it exits the script if one is found.
    test_lockfile

    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ 
    # This script relies on 'wget' to download builds from
    # the Jenkins server; make sure that 'wget' is available
    # on this platform.
    which wget
    if [ $? -ne 0 ]
    then
        log "Exiting because wget is not available on this computer."
        exit $E_WGETNOTAVAILABLE
    fi



}




test_latest_build()
{


    local TESTBUILD=$1

    if [ -z $TESTBUILD ]
    then
        log "test_latest_build() wasn't passed a build number - aborting"
        return 7
    fi

    FWIMAGE=`find $TESTBUILD -iname "app*.img.gz"`


    log "Testing Build number $TESTBUILD (file $FWIMAGE)"

    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_
    # All of these tests require us to communicate with the outlet
    # via the USB/BLE dongle - which means we need to know
    # the MAC address. Problem is, the outlet uses one MAC
    # address in the non-configured state, and another in
    # the configured state. So we have to figure out which
    # one it's using:
    scanmacaddrs
    if [ $? -ne 0 ]
    then
        log "scanmacaddrs() failed while attempting to setup for tests of build number $TESTBUILD"
        return 5
    fi

    log "scanmacaddrs() succeeded in collecting MAC addresses active in the immediate vicinity"

    sleep 5

    # Now compare our pair of MAC addresses (stored in files
    # "macaddr-configured.txt" and "macaddr-deconfigured.txt")
    # with the addresses we found during our scan:
    findmac
    if [ $? -ne 0 ]
    then
        log "findmac() failed while attempting to setup for tests of build number $TESTBUILD"
        return 6
    fi
    
    log "findmac() determined that the outlet's current MAC address is $MACADDR."

    # OK -- we've got the current MAC address for our outlet, on to the tests:

	TESTLEVEL=`cat .$TESTBUILD`
	log "Currently have completed $TESTLEVEL of 2 tests against Jenkins Build number $TESTBUILD (file $FWIMAGE)"

	if [ $TESTLEVEL -eq 0 ]
	then

		sleep 5

		log "Starting ota_test() for build number $TESTBUILD"
		# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_
		# Test 1/4 - Attempt an OTA update with the latest build:
		ota_test
		if [ $? -eq 0 ]
		then
			log "ota_test() succeeded for build number $TESTBUILD"
			echo "1" > .$LATESTBUILD
		else
			log "ota_test() failed for build number $TESTBUILD"
			return 1
		fi
	fi


	if [ $TESTLEVEL -eq 1 ]
	then

		# Bring the hci0 interface down before trying again
		sudo hciconfig hci0 down

		sleep 5

		log "Starting version_test() for build number $TESTBUILD"
		# \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_
		# Test 2/4 - Query the outlet for its version number to
		# see if it matches the version (git commit sha) of the
		# file that was OTA udpated:
		version_test
		if [ $? -eq 0 ]
		then
			log "version_test() succeeded for build number $TESTBUILD"
			echo "2" > .$LATESTBUILD
		else
			log "version_test() failed for build number $TESTBUILD"
			return 2
		fi
	fi


	log "Skipping configure/deconfigure tests for build number $TESTBUILD (still unstable)"

    # sleep 5

    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_
    # Test 3/4 - Attempt to configure the outlet:
    # configure_test
    # if [ $? -eq 0 ]
    # then
    #     log "configure_test() succeeded for build number $TESTBUILD"
    # else
    #     log "configure_test() failed for build number $TESTBUILD"
    #     return 3
    # fi

    # sleep 5

    # \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_ \_\_\_\_
    # Test 4/4 - Attempt to de-configure the outlet:
    # deconfigure_test    
    # if [ $? -eq 0 ]
    # then
    #     log "deconfigure_test() succeeded for build number $TESTBUILD"
    # else
    #     log "deconfigure_test() failed for build number $TESTBUILD"
    #     return 4
    # fi


    # Signal that all the tests succeeded
    return 0
}
