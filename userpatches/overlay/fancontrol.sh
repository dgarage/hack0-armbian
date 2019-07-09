#!/bin/bash

set -e

: "${TEMP_MIN:=45}"
: "${TEMP_MAX:=60}"
: "${TEMP_FILE:=/sys/class/thermal/thermal_zone0/temp}"
: "${TEMP_COOLDOWN:=40}"
: "${FAN_MIN:=120}"
: "${FAN_MAX:=255}"
: "${FAN_KICKSTART:=0}"
: "${CYCLE:=10}"
: "${VERBOSE:=false}"

if [[ -z "${FAN_FILE}" ]]; then
    FAN_FILE=$(ls /sys/devices/platform/pwm-fan/hwmon/*/pwm1)
    echo "Fan detected at $FAN_FILE"
fi

ECHO="true || "
if "$VERBOSE"; then
    ECHO="echo"
fi

if [ "$TEMP_COOLDOWN" -gt "$TEMP_MIN" ] || [ "$TEMP_MIN" -gt "$TEMP_MAX" ]; then
	echo "Inconsistent temperature range"
	exit 1
fi

cooldown=false
while true; do
    temp=$(<$TEMP_FILE)
    temp=$((temp/1000))
    $ECHO "Current temperature: $temp"
    fanpwm=$(($FAN_MIN + ( ( $FAN_MAX - $FAN_MIN ) / ( $TEMP_MAX - $TEMP_MIN ) ) * ( $temp - $TEMP_MIN ) ))
    if [ "$fanpwm" -gt "$FAN_MAX" ]; then
	    fanpwm=$FAN_MAX
    elif [ "$fanpwm" -lt "$FAN_MIN" ]; then
	    fanpwm=$FAN_MIN
    fi
    if $cooldown; then
        if [ "$fanpwm" -lt "$FAN_MIN" ]; then
	    fanpwm=$FAN_MIN
        fi
        if [ "$temp" -lt "$TEMP_COOLDOWN" ]; then
            fanpwm=0
	    cooldown=false
	    $ECHO "Fan turned off"
	else
	    $ECHO "The temperature ($temp c) is still more or equal to the cooldown temperature ($TEMP_COOLDOWN), keep the fan turned on."
	fi
    elif [ "$temp" -ge "$TEMP_MIN" ]; then
	    cooldown=true
	    $ECHO "The temperature ($temp c) is more or equal to the desired temperature ($TEMP_MIN c), turning on the fan."
	    if [ "$FAN_KICKSTART" -ne "0" ]; then
		    $ECHO "Kickstart for $FAN_KICKSTART seconds."
		    echo "$FAN_MAX" > "$FAN_FILE"
		    sleep "$FAN_KICKSTART"
	    fi
    else
	    $ECHO "The temperature ($temp c) is less than the desired temperature ($TEMP_MIN c), turn off the fan."
	    fanpwm=0
    fi

    $ECHO "FAN PWM: $fanpwm"
    echo "$fanpwm" > "$FAN_FILE"
    sleep "$CYCLE"
done
