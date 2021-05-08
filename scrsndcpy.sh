#!/bin/bash

SCRCPY=scrcpy
SCRCPY_ARGS=
SNDCPY_HOME=/home/hekinami/Workspace/git/sndcpy
SCRCPY_PID_FILE=/run/user/$UID/scrsndcpy_scrcpy.pid
SNDCPY_PID_FILE=/run/user/$UID/scrsndcpy_sndcpy.pid

ANDROID_HOME=/home/hekinami/Android/Sdk
JRE_HOME=/home/hekinami/Workspace/Development/android-studio/jre
PATH=$JRE_HOME/bin:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools:$PATH

list_process_descendants () {
  local children=$(ps -o pid= --ppid "$1")

  for pid in $children
  do
    list_process_descendants "$pid"
  done

  [ -n "$children" ] && echo "$children"
}

kill_process_and_descendants () {
    local self="$1"
    local descendants=$(list_process_descendants $self)
    [ -n "$descendants" ] && kill -9 $descendants
    kill -9 $self 2> /dev/null
}

save_scrcpy_pid () {
    echo -n "$SCRCPY_PID" > "$SCRCPY_PID_FILE"
}

save_sndcpy_pid () {
    echo -n "$SNDCPY_PID" > "$SNDCPY_PID_FILE"
}

remove_scrcpy_pid () {
    rm -f $SCRCPY_PID_FILE
}

remove_sndcpy_pid () {
    rm -f $SNDCPY_PID_FILE
}

load_pid () {
    [ -e "$SCRCPY_PID_FILE" ] && SCRCPY_PID=$(cat $SCRCPY_PID_FILE)
    [ -e "$SNDCPY_PID_FILE" ] && SNDCPY_PID=$(cat $SNDCPY_PID_FILE)
}

check_if_phone_not_muted () {
    STATUS=$(adb shell dumpsys audio | \
                awk '/^- STREAM_MUSIC/ {getline; print}' | \
                cut -d':' -f2 | cut -d' ' -f2)
    [ "false" == ${STATUS} ]
}

mute_if_needed () {
    check_if_phone_not_muted && adb shell input keyevent 164 # press KEY_MUTE
}

unmute_if_needed () {
    ! check_if_phone_not_muted && adb shell input keyevent 164 # press KEY_MUTE
}

wait_sndcpy_port_availability () {
    echo "waiting sndcpy port ready..."
    local count=$(netstat -an | awk '$4~/127.0.0.1:28200/ && $6~/LISTEN/ {count++} END {print count}')
    while true; do
        local count=$(netstat -an | awk '$4~/127.0.0.1:28200/ && $6~/LISTEN/ {count++} END {print count}')
        count=${count:-0}
        [ 1 -eq $count ] && break
    done
}

start_scrcpy () {
    echo "starting scrcpy"
    bash -c "${SCRCPY} ${SCRCPY_ARGS}" >/dev/null 2>&1 &
    if [ $? -eq 0 ]; then
        SCRCPY_PID=$!
        save_scrcpy_pid
        echo "scrcpy started."
    else
        echo "error: failed to start scrcpy."
    fi
}

stop_scrcpy () {
    [ -n "${SCRCPY_PID}" ] && kill_process_and_descendants ${SCRCPY_PID} && echo "scrcpy stopped."
    remove_scrcpy_pid
}

sndcpy_run () {
    local sndcpy_apk=app/build/outputs/apk/debug/app-debug.apk
    local sndcpy_port=28200

    adb install -t -r -g "$sndcpy_apk" ||
        {
            adb uninstall com.rom1v.sndcpy
            adb install -t -g "$sndcpy_apk"
        }

    adb forward tcp:$sndcpy_port localabstract:sndcpy
    adb shell appops set com.rom1v.sndcpy PROJECT_MEDIA allow
    adb shell am start com.rom1v.sndcpy/.MainActivity
    # echo "Press Enter once audio capture is authorized on the device to start playing..."
    # read dummy
    # wait_sndcpy_port_availability
    sleep 5
    vlc -Idummy --demux rawaud --network-caching=0 --play-and-exit tcp://localhost:"$sndcpy_port" >/dev/null 2>&1 &
    
}

start_sndcpy () {
    echo "starting sndcpy"

    pushd ${SNDCPY_HOME} > /dev/null

    sndcpy_run
    if [ $? -eq 0 ]; then
        SNDCPY_PID=$!
        save_sndcpy_pid
        mute_if_needed
        echo "sndcpy started."
    else
        echo "error: failed to start sndcpy."
    fi

    popd  > /dev/null
}

stop_sndcpy () {
    [ -n "${SNDCPY_PID}" ] && kill_process_and_descendants ${SNDCPY_PID} && echo "sndcpy stopped."
    remove_sndcpy_pid
    unmute_if_needed
}

start () {
    start_scrcpy
    start_sndcpy
}

stop () {
    load_pid
    stop_scrcpy
    stop_sndcpy
}

ACTION=${1:-start}

if [ "start" == "$ACTION" ]; then
    start
elif [ "stop" == "$ACTION" ]; then
    stop
else
    echo "usage: scrsndcpy.sh {start|stop}"
fi

