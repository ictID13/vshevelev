#!/usr/bin/env bash


clear;
echo "====================================================================================================";
echo " ADB DEVICES";
echo "====================================================================================================";
echo "";

adb_devices=( $(adb devices | grep -v devices | grep device | cut -f 1)#$(adb devices | grep -v devices | grep device | cut -f 2) );

if [ $((${#adb_devices[@]})) -eq "1" ] && [ "${adb_devices[0]}" == "#" ]
then
    echo "No device found";
    echo ""; 
    echo "====================================================================================================";
    device=""
#    // Call Main Menu function fxMenu;
else
    read -p "$(
        f=0
        for dev in "${adb_devices[@]}"; do
            nm="$(echo ${dev} | cut -f1 -d#)";
            tp="$(echo ${dev} | cut -f2 -d#)";
            echo " $((++f)). ${nm} [${tp}]";
        done
  echo "";
        echo " 0. Quit"
        echo "";

        echo "====================================================================================================";
        echo "";
        echo ' Please select a device: '
    )" selection

    error="You think it's over just because I am dead. It's not over. The games have just begun.";
 #// Call Validation Numbers fxValidationNumberMenu ${#adb_devices[@]} ${selection} "${error}"
    case "${selection}" in
        0)
           exit 0;;
        *)
            echo ${adb_devices[$((selection-1))]} | cut -f1 -d#;;
    esac
fi
