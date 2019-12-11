#!/bin/bash
########################################################################################################################
#
#  ##     ## ########    ###    ########  ######## ########  
#  ##     ## ##         ## ##   ##     ## ##       ##     ## 
#  ##     ## ##        ##   ##  ##     ## ##       ##     ## 
#  ######### ######   ##     ## ##     ## ######   ########  
#  ##     ## ##       ######### ##     ## ##       ##   ##   
#  ##     ## ##       ##     ## ##     ## ##       ##    ##  
#  ##     ## ######## ##     ## ########  ######## ##     ## 
#
########################################################################################################################
. $(dirname $0)/../tools/common.sh
# DEBUG=0
# echo_title $*

# http://www.network-science.de/ascii/ font banner
########################################################################################################################
#
#   ##     ##    ###    ########   ######  
#   ##     ##   ## ##   ##     ## ##    ## 
#   ##     ##  ##   ##  ##     ## ##       
#   ##     ## ##     ## ########   ######  
#    ##   ##  ######### ##   ##         ## 
#     ## ##   ##     ## ##    ##  ##    ## 
#      ###    ##     ## ##     ##  ######  
#
########################################################################################################################
EXTRAOPTIONS=""
MODE_HOST=0
MODE_SERVICE=1
PLUGIN_MODE=MODE_HOST
STATUS=$CENTREON_STATE_OK
STATUS_EXTENDED_INFORMATION=""
PERFDATA=""
POLLER_HIGH_LIST=""

########################################################################################################################
#
#   ##     ##    ###    #### ##    ## 
#   ###   ###   ## ##    ##  ###   ## 
#   #### ####  ##   ##   ##  ####  ## 
#   ## ### ## ##     ##  ##  ## ## ## 
#   ##     ## #########  ##  ##  #### 
#   ##     ## ##     ##  ##  ##   ### 
#   ##     ## ##     ## #### ##    ## 
#
########################################################################################################################

for ARG in "$@"
do
	if [[ "$ARG" =~ ^--service-warning-count=(.*)$ ]]; then
		CENTREON_SERVICE_WARNING_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--service-critical-count=(.*)$ ]]; then
		CENTREON_SERVICE_CRITICAL_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--service-max-count=(.*)$ ]]; then
		CENTREON_SERVICE_MAX_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--host-warning-count=(.*)$ ]]; then
		CENTREON_HOST_WARNING_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--host-critical-count=(.*)$ ]]; then
		CENTREON_HOST_CRITICAL_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--host-max-count=(.*)$ ]]; then
		CENTREON_HOST_MAX_COUNT=${BASH_REMATCH[1]}
	elif [[ "$ARG" =~ ^--mode=(.*)$ ]]; then
		# To be done
		MODE=${BASH_REMATCH[1]}
		[[ "$MODE" = [Hh][Oo][Ss][Tt] ]] && PLUGIN_MODE=$MODE_HOST
		[[ "$MODE" = [Ss][Ee][Rr][Vv][Ii][Cc][Ee] ]] && PLUGIN_MODE=$MODE_SERVICE
	else
		EXTRAOPTIONS="$EXTRAOPTIONS $ARG"
	fi
done



while read line
do
	POLLERNAME=$(echo $line | awk -F';' '{ print $2 }')
	
	POLLER_HIGH_SERVICE=""
	POLLER_HIGH_HOST=""
	SQL_REQUEST="SELECT COUNT(service_id) FROM centreon_storage.services s JOIN centreon_storage.hosts h ON (s.host_id = h.host_id) JOIN centreon_storage.instances i ON (h.instance_id = i.instance_id) WHERE i.name = '$POLLERNAME'"
	SCOUNT=`mysql -u$db_user -p$db_passwd -h $db_host -D $centstorage_db -N -e "$SQL_REQUEST;"`
	if [[ $SCOUNT -gt $CENTREON_SERVICE_WARNING_COUNT && $STATUS -ge $CENTREON_STATE_OK ]]; then
		STATUS=$CENTREON_STATE_WARNING
		POLLER_HIGH_SERVICE="${POLLERNAME} ($SCOUNT services)"
	fi
	if [[ $SCOUNT -gt $CENTREON_SERVICE_CRITICAL_COUNT && $STATUS -ge $CENTREON_STATE_WARNING ]]; then
		STATUS=$CENTREON_STATE_CRITICAL
		POLLER_HIGH_SERVICE="${POLLERNAME} ($SCOUNT services)"
	fi
	# SPERC=`expr $SCOUNT \* 100 \/ $CENTREON_SERVICE_CRITICAL_COUNT`
	SQL_REQUEST="SELECT COUNT(host_id) FROM centreon_storage.hosts h JOIN centreon_storage.instances i ON (h.instance_id = i.instance_id) WHERE i.name = '$POLLERNAME'"
	HCOUNT=`mysql -u$db_user -p$db_passwd -h $db_host -D $centstorage_db -N -e "$SQL_REQUEST;"`
	if [[ $HCOUNT -gt $CENTREON_HOST_WARNING_COUNT && $STATUS -ge $CENTREON_STATE_OK ]]; then
		STATUS=$CENTREON_STATE_WARNING
		POLLER_HIGH_HOST="${POLLERNAME} ($HCOUNT hosts)"
	fi
	if [[ $HCOUNT -gt $CENTREON_HOST_CRITICAL_COUNT && $STATUS -ge $CENTREON_STATE_WARNING ]]; then
		STATUS=$CENTREON_STATE_CRITICAL
		POLLER_HIGH_HOST="${POLLERNAME} ($HCOUNT hosts)"
	fi
	# HPERC=`expr $HCOUNT \* 100 \/ $CENTREON_HOST_CRITICAL_COUNT`
	
	
	STATUS_EXTENDED_INFORMATION="${STATUS_EXTENDED_INFORMATION}${POLLERNAME} : ${HCOUNT} hosts and $SCOUNT services\n"
	[[ ! "$POLLER_HIGH_SERVICE" = "" ]] && POLLER_HIGH_LIST="${POLLER_HIGH_LIST}${POLLER_HIGH_SERVICE},"
	[[ ! "$POLLER_HIGH_HOST" = "" ]] && POLLER_HIGH_LIST="${POLLER_HIGH_LIST}${POLLER_HIGH_HOST},"
		
		# 'label'=value[UOM];[warn];[crit];[min];[max]
		
	PERFDATA="${PERFDATA}'${POLLERNAME}_hosts'=$HCOUNT;${CENTREON_HOST_WARNING_COUNT};${CENTREON_HOST_CRITICAL_COUNT};0;${CENTREON_HOST_MAX_COUNT} "
	PERFDATA="${PERFDATA}'${POLLERNAME}_services'=$SCOUNT;${CENTREON_SERVICE_WARNING_COUNT};${CENTREON_SERVICE_CRITICAL_COUNT};0;${CENTREON_SERVICE_MAX_COUNT} "
		
done < <(${CLAPIBIN} -u ${CLAPIUSR} -p ${CLAPIPWD} -a POLLERLIST | grep -vE "Return code|poller_id" | sort -t';' -k 2 )

[[ ! "$STATUS_EXTENDED_INFORMATION" = "" ]] && STATUS_EXTENDED_INFORMATION=${STATUS_EXTENDED_INFORMATION::-2}
[[ ! "$PERFDATA" = "" ]] && PERFDATA=${PERFDATA::-1}
[[ ! "$POLLER_HIGH_LIST" = "" ]] && POLLER_HIGH_LIST=${POLLER_HIGH_LIST::-1}

[[ $STATUS -eq $CENTREON_STATE_OK ]] && echo -e "OK : All poller load is correct.\n${STATUS_EXTENDED_INFORMATION} | ${PERFDATA}"
[[ $STATUS -eq $CENTREON_STATE_WARNING ]] && echo -e "WARNING : Poller load is high for ${POLLER_HIGH_LIST}.\n${STATUS_EXTENDED_INFORMATION} | ${PERFDATA}"
[[ $STATUS -eq $CENTREON_STATE_CRITICAL ]] && echo -e "CRITICAL : Poller load is very high for ${POLLER_HIGH_LIST}.\n${STATUS_EXTENDED_INFORMATION} | ${PERFDATA}"
# echo_end
exit $STATUS

