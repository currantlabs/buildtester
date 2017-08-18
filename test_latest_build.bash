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
BUILDNO=62
RETRIES=5
FWBURNTIME=30

# At startup, there are some things you need to do:
# (1) find the firmware image (i.e., the app)
# (2) remove the MACADDRSCANRESULTS file so you force a refresh
# (3) log-in to the backend so that you can run all of the tests

# echo "Welcome to test_latest_build()"

FWIMAGE=`find $BUILDNO -iname "app*.img.gz"`
sudo rm -f $MACADDRSCANRESULTS

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


ota_test()
{
    attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo ./ziggy client upgrade  --application=$FWIMAGE --install=true $MACADDR > /dev/null 2> /dev/null

        if [ $? -ne 0 ]
        then
            echo "OTA update failed on attempt $attempts."
            if [ $attempts -eq $RETRIES ]
            then
                break
            else
                sleep 2
            fi
        else
            echo "OTA update succeeded on attempt $attempts."
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
    #echo "Waiting for hardware to flash the new application image..."
    sleep $FWBURNTIME

    return 0
}

reset_ble()
{
	echo "Before reset of device \"sudo hcitool dev\" says:"
	echo "-------- -------- -------- --------"
	sudo hcitool dev
	echo "-------- -------- -------- --------"

	sudo hciconfig hci0 reset

	echo "After reset of device \"sudo hcitool dev\" says:"
	echo "-------- -------- -------- --------"
	sudo hcitool dev
	echo "-------- -------- -------- --------"

}

version_test()
{
    local RESULTFILE=/tmp/version
    local GITSHA=`echo $FWIMAGE | sed 's/^.*-\([a-z0-9]*\)\\.img\\.gz.*$/\1/'`
    echo "Testing the new application image for $GITSHA"

    attempts=0
	
	local lines

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

		sudo ./ble-console -addr $MACADDR -command version | sudo tee $RESULTFILE > /dev/null 

        OUTPUTSIZE=`stat --format="%s" $RESULTFILE`

        if [ $OUTPUTSIZE -eq 0 ]
        then
            echo "Attempt to capture FW version data failed on attempt $attempts."
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
			echo "Only captured $lines lines of data - looks like a BT communications problem. Trying again..."
			echo "-------- -------- -------- --------"
			cat $RESULTFILE
			echo "-------- -------- -------- --------"
			reset_ble
			sleep 2
			continue
		fi
		


        echo "Attempt to collect FW version data succeeded on attempt $attempts."
		echo "-------- -------- -------- --------"
		cat $RESULTFILE
		echo "-------- -------- -------- --------"

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
        echo "The \"App version String\" does not contain the expected git commit sha, $GITSHA"
        return 1
    fi

    echo "Version string matches"
    return 0
}

configure_test()
{
    if [ -z $MACADDR ]
    then
        echo "Have not determined the MAC address - first run scanmacaddrs(), and then run findmac()."
		return 4
    fi

    local attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

		sudo rm -f $SETUPRESULTS

        sudo LOGXI=* ./ziggy --prod client setup --lid="$LOCATIONID" $MACADDR > $SETUPRESULTS

        grep -q "client error connecting" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            sleep 2
            continue
        fi

        grep -q "no devices available" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            return 2
        fi

        grep -q "client could not find device mac" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            return 3
        fi


        grep -q "client device successfully configured" $SETUPRESULTS
        if [ $? -eq 0 ]
        then
            # The MAC address has changed so reset the MAC address scan results file
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
    if [ -z $MACADDR ]
    then
        echo "Have not determined the MAC address - first run scanmacaddrs(), and then run findmac()."
		return 4
    fi

    local attempts=0

    until [ $attempts -ge $RETRIES ]
    do
        attempts=$[$attempts+1]

        sudo ./ziggy --prod client clear $MACADDR > $CLEARRESULTS

        grep -q "client error connecting" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            sleep 2
            continue
        fi

        grep -q "no devices available" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            return 2
        fi

        grep -q "client could not find device mac" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            return 3
        fi

        grep -q "client device successfully deconfigured" $CLEARRESULTS
        if [ $? -eq 0 ]
        then
            # The MAC address has changed so reset the MAC address scan results file
            rm -f $MACADDRSCANRESULTS
            MACADDR=""
            return 0
        fi


    done

    return 1

    
}

deconfigure()
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
        echo "Must scan for MAC addresses (call scanmacaddrs()) before you can determine the device's current MAC address."
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
        echo "Have not determined the MAC address - first run scanmacaddrs(), and then run findmac()."
    else
        echo "The MAC address is $MACADDR"
    fi

}



getapp()
{
	echo "Get the proposition app for this build number: $1"
	wget -q -r -l3 -np http://jenkins.currant.com/images/ -P $1 -A "app$1*.img.gz"

}

getbl()
{
	echo "Get the booloader for this build number: $1"
	wget -q -r -l3 -np http://jenkins.currant.com/images/ -P $1 -A "bl$1*.img.gz"

}


# OK, this is the code that is actually _run_ when the file is sourced:
echo -n "Determining the MAC address of the unit under test..."
scanmacaddrs
findmac
if [ -z $MACADDR ]
then
    echo
    echo "Could not determine the MAC address of the unit under test - check your setup."
    exit 1
else
    echo "MAC address of the device under test is $MACADDR"
fi
