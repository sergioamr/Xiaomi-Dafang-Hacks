#!/bin/sh

# Takes a snapshot every N seconds interval configured
# in /system/sdcard/config/timelapse.conf

. /system/sdcard/config/motion.conf

PIDFILE='/run/timelapse.pid'
TIMELAPSE_CONF='/system/sdcard/config/timelapse.conf'
BASE_SAVE_DIR='/system/sdcard/DCIM/timelapse'

if [ -f "$TIMELAPSE_CONF" ]; then
    . "$TIMELAPSE_CONF" 2>/dev/null
fi

if [ -z "$TIMELAPSE_INTERVAL" ]; then TIMELAPSE_INTERVAL=2.0; fi


# because``date`` doesn't support milliseconds +%N
# we have to use a running counter to generate filenames
counter=0
last_prefix=''
ts_started=$(date +%s)

while true; do
    SAVE_DIR=$BASE_SAVE_DIR
    if [ $SAVE_DIR_PER_DAY -eq 1 ]; then
        SAVE_DIR="$BASE_SAVE_DIR/$(date +%Y-%m-%d)"
    fi
    if [ ! -d "$SAVE_DIR" ]; then
        mkdir -p $SAVE_DIR
    fi
    filename_prefix="$(date +%Y-%m-%d_%H%M%S)"
    if [ "$filename_prefix" = "$last_prefix" ]; then
        counter=$(($counter + 1))
    else
        counter=1
        last_prefix="$filename_prefix"
    fi
    counter_formatted=$(printf '%03d' $counter)
    filename="${filename_prefix}_${counter_formatted}.jpg"
    if [ -z "$COMPRESSION_QUALITY" ]; then
         /system/sdcard/bin/getimage > "$SAVE_DIR/$filename" 
    else
        /system/sdcard/bin/getimage | /system/sdcard/bin/jpegoptim -m"$COMPRESSION_QUALITY" --stdin --stdout > "$SAVE_DIR/$filename" 
    fi

    snapshot_tempfile=$SAVE_DIR/$filename
    echo "SAVE $snapshot_tempfile"
    ls $snapshot_tempfile -la

    # FTP snapshot and video stream
    if [ "$ftp_snapshot" = true -o "$ftp_video" = true ]; then
        (
        echo "FTP UPLOAD"
        ftpput_cmd="/system/sdcard/bin/busybox ftpput"
        if [ "$ftp_username" != "" ]; then
                ftpput_cmd="$ftpput_cmd -u $ftp_username"
        fi
        if [ "$ftp_password" != "" ]; then
                ftpput_cmd="$ftpput_cmd -p $ftp_password"
        fi
        if [ "$ftp_port" != "" ]; then
                ftpput_cmd="$ftpput_cmd -P $ftp_port"
        fi
        ftpput_cmd="$ftpput_cmd $ftp_host"

        if [ "$ftp_snapshot" = true ]; then
                echo "Sending FTP snapshot to ftp://$ftp_host/$ftp_stills_dir/$filename"
                $ftpput_cmd "$ftp_timelapse_dir/$filename" $snapshot_tempfile

        echo ""
        echo " $ftpput_cmd "$ftp_timelapse_dir/$filename" $snapshot_tempfile "
        echo ""
        fi

        ) &
    fi

    sleep $TIMELAPSE_INTERVAL

    if [ $TIMELAPSE_DURATION -gt 0 ]; then
        ts_now=$(date +%s)
        elapsed=$(($ts_now - $ts_started))
        if [ $(($TIMELAPSE_DURATION * 60)) -le $elapsed ]; then
            break
        fi
    fi
  
done

# loop completed so let's purge pid file
rm "$PIDFILE"
