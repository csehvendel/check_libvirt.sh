#!/bin/bash
# v1
# initial relase 2018.08.04

OK=0
WARN=0
CRIT=0


function vm_status () {
	RUNNING=0
	NONRUNNING=0
	CRASHED=0
	for vmstatus in $( virsh -c $TYPE://$UN@$HOST/system --readonly list --all | sed '1,2d' | sed '/^$/d' | awk '{print $2":"$3}' )
	do
		NAME=$(echo $vmstatus | awk -F: '{print $1}')
		STATUS=$(echo $vmstatus | awk -F: '{print $2}')
		case "$STATUS" in
			running)
				RUNNING=$(expr $RUNNING + 1)
			;;
			paused|shutdown|shut*)
				NONRUNNING=$(expr $NONRUNNING + 1)
			;;
			crashed|dying)
				CRASHED=$(expr $CRASHED + 1)
			;;
		esac
	done

        PERFDATA=$(echo "running_VM=$RUNNING;;, non_running_VM=$NONRUNNING;;, crashed_VM=$CRASHED;;")

	if [ "$RUNNING" -gt 0 ]
	then
		OK=$(expr $OK + 1)
	fi

	if [ "$NONRUNNING" -gt 0 ]
	then
		WARN=$(expr $WARN + 1)
	fi

	if [ "$CRASHED" -gt 0 ]
	then
		CRIT=$(expr $CRIT + 1)
	fi

	if [ "$WARN" -eq 1 ]
	then
		echo "WARNING $NONRUNNING VM not running | $PERFDATA"
		exit 1
	elif	[ "$CRIT" -eq 1 ]
	then
		echo "CRITICAL $CRASHED VM | $PERFDATA"
		exit 2
	else
	   echo "OK $RUNNING VM running | $PERFDATA"
      exit 0
	fi
}

function pool_status () {
	ACTIVEPOOL=0
	INACTIVEPOOL=0
	for poolstatus in $( virsh -c $TYPE://$UN@$HOST/system --readonly pool-list --all | sed '1,2d' | sed '/^$/d' | awk '{print $1":"$2}')
	do
                POOLNAME=$(echo $poolstatus | awk -F: '{print $1}')
                POOLSTATUS=$(echo $poolstatus | awk -F: '{print $2}')
		case $POOLSTATUS in
			active)
				ACTIVEPOOL=$(expr $ACTIVEPOOL + 1)
			;;
			inactive)
				INACTIVEPOOL=$(expr $INACTIVEPOOL + 1)
			;;
		esac
	done
	PERFDATA=$(echo "active_pools=$ACTIVEPOOL;;, inactive_pools=$INACTIVEPOOL;;")
	if [ "$INACTIVEPOOL" -gt 0 ]
	then
		echo "WARNING there are $INACTIVEPOOL inactive pool | $PERFDATA"
		exit 1
	fi
	echo "OK there are $ACTIVEPOOL active pool | $PERFDATA"
	exit 0
}

function pool_usage () {
	POOLOK=0
	POOLWARN=0
	POOLCRIT=0
	declare -a PERFDATA=()
	for pool in $(virsh -c $TYPE://$UN@$HOST/system --readonly pool-list | grep active | awk '{print $1}')
	do
		POOLPARAMS=$(virsh -c $TYPE://$UN@$HOST/system --readonly pool-info --bytes $pool | grep -e "Name:" -e "Capacity:" -e "Allocation:" | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' | awk '{print $2":"$4":"$6}')
		POOLNAME=$(echo $POOLPARAMS | awk -F: '{print $1}')
		POOLCAPACITY=$(echo $POOLPARAMS | awk -F: '{print $2}')
		POOLALLOCATION=$(echo $POOLPARAMS | awk -F: '{print $3}')
 		POOLUSAGE100=$(( $POOLCAPACITY / 100 ))
 		POOLUSAGE=$(( $POOLALLOCATION / $POOLUSAGE100 ))
 		if [ "$POOLUSAGE" -gt "$CRITICAL" ]
 			then
 				POOLCRIT=$(expr "$POOLCRIT" + 1)
 		elif [ "$POOLUSAGE" -lt "$WARNING" ]
 			then
 				POOLOK=$(expr $POOLOK + 1)
 		else
 				POOLWARN=$(expr $POOLWARN + 1)
		fi
		PERFDATA+=$(echo -n "pool_$POOLNAME=$POOLUSAGE;$WARNING;$CRITICAL, ")
	done
	
	if [ "$POOLOK" -gt 0 ]
	then
		OK=$(expr $OK + 1)
	fi

	if [ "$POOLWARN" -gt 0 ]
	then
		WARN=$(expr $WARN + 1)
	fi

	if [ "$POOLCRIT" -gt 0 ]
	then
		CRIT=$(expr $CRIT + 1)
	fi

	if [ "$WARN" -eq 1 ]
	then
		echo "WARNING 1 or more active pool on warning threshold | ${PERFDATA[@]}"
		exit 1
	elif	[ "$CRIT" -eq 1 ]
	then
		echo "CRITICAL 1 or more active pool on critical threshold | ${PERFDATA[@]}"
		exit 2
	else
	   echo "OK all active pool below on warning threshold | ${PERFDATA[@]}"
      exit 0
	fi
}

function help {
		echo "Usage:"
		echo ""
		echo "install virsh on icinga/nagios host"
		echo ""
		echo "check the nagios user can connect to remote libvirt machine"
		echo " ex. sudo nagios virsh -c qemu+ssh://user@remote.libvirt.machine/system --readonly list"
		echo ""
		echo "If all looks good put the command into your icinga/nagios"
		echo ""
		echo "check_libvirt -H libvirt-uri -m mode <-w warning -c critical>"
		echo ""
		echo "-H (libvirt host)"
		echo "	The remote libvirt host"
		echo "	!!! mandatory argument !!!"
		echo ""
		echo "-u (username)"
		echo "	Username to connect to hypervisor"
		echo "	!!! mandatory argument !!!"
		echo ""
		echo "-t (connection type)"
		echo "	currently only qemu+ssh supported, this is default" 	
		echo "-m (mode):"
		echo "	vm_status"
		echo "		check virtual machines status (running,paused etc...)"
		echo "		returns WARNING when one ore more VM powerwed off or paused"
		echo "		returns CRITICAL when one or more VM crashed"
		echo ""
		echo "	pool_status"
		echo "		check definied storage pools"
		echo "		returns warning when inactive pool founded"
		echo ""
		echo "-w (warning)"
		echo "	Warning threshonld in percentage"
		echo "	Default: 80%"
		echo ""
		echo "-c (critital)"
		echo "	Critical threshold in percentage"
		echo "	Default: 95%"
		echo ""
		echo "You can donate the plugin via PayPal (csehvendel@gmail.com)"
		exit 0
}

function check_wc () {
		if [ "$WARNING" -gt "$CRITICAL" ]
			then
				echo "WARNING is greater than critical!"
				exit 3
		fi
}


if [ "$1" = "--help" ]
then
    help
fi
if [ "$1" = "-h" ]
then
    help
fi
if [ -z "$1" ]
then
    help
fi

while getopts ":H:w:c:m:u:t:" opts
do
	case ${opts} in
		H)
				HOST=${OPTARG}
		;;
		w)
				WARNING=${OPTARG}
		;;
		c)
				CRITICAL=${OPTARG}
		;;
		m)
			   MODE=${OPTARG}
		;;
		u)
				UN=${OPTARG}
		;;
		t)
				TYPE=${$OPTARG}
		;;
		*)
				help
	esac
done

if [ -z "$HOST" ]
	then
		help
fi
if [ -z "$UN" ]
	then
		help
fi
if [ -z "$WARNING" ]
	then
		WARNING=80
fi
if [ -z "$CRITICAL" ]
	then
		CRITICAL=95
fi
if [ -z "$TYPE" ]
	then
		TYPE="qemu+ssh"
fi
if [ -z "$MODE" ]
	then
		help
fi
if [ $MODE = vm_status ]
	then
		vm_status
fi
if [ $MODE = pool_status ]
	then
		pool_status
fi
if [ $MODE = pool_usage ]
   then
   	check_wc
      pool_usage
fi
