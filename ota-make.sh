#!/bin/sh

# -----------------------------------------------------------------------------
# Скрипт написан без использования расширенных возможностей bash.
# Должен нормально работать везде, где есть POSIX shell и coreutils.
# -----------------------------------------------------------------------------

set +e
set -u
#set -x

trap "adb disconnect 2> /dev/null 1> /dev/null" INT TERM HUP QUIT EXIT

MYSELF=$(which "$0" 2>/dev/null)
[ $? -gt 0 -a -f "$0" ] && MYSELF="./$0"
ADBSCAN="${MYSELF%/*}/adbscan"
[ -f $ADBSCAN ] || ADBSCAN=""
MYSELF="${MYSELF##*/}"
CMD_HANDLER=""

APK_VERSION="20160101"  # это версия дефолтного стора, которую OTA запишет в конфиги


# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
funShowUsage () {
    echo "Usage: $MYSELF <command> [params]"
    echo
    if [ -n "$ADBSCAN" ] ; then
        echo "  $MYSELF info [<ip-addr>]"
    else
        echo "  $MYSELF info <ip-addr>"
    fi
    echo "    Shows model, Android version, build date"
    echo "    and location of files, required for OTA script."
    echo
    echo "  $MYSELF script <ip-addr> [utc-date]"
    echo "    Shows both scripts prepared for OTA update."
    echo "    Do not create or update OTA archive."
    echo
    echo "  $MYSELF arch <ip-addr> [utc-date]"
    echo "    Create OTA archive for specified device."
    echo "    Requred 'zip' tool installed and presence of 'ota-arch' directory."
    if [ -n "$ADBSCAN" ] ; then
        echo
        echo "  $MYSELF scan"
        echo "    Shows brief report for all ADB devices in local net"
    fi
    echo
    echo "  Examples:"
    echo "    $MYSELF info 192.168.0.200"
    echo "    $MYSELF script 192.168.0.200 \"@1583020800\""
    echo "    $MYSELF arch 192.168.0.200 \"2020-03-01\""
    echo
}

# -----------------------------------------------------------------------------
# Ищет раздел и точку монтирования для указанного файла
# -----------------------------------------------------------------------------
funCheckFS () {
    MNT_APP=$(adb shell "${CMD_HANDLER}df $1")
    MNT_APP=$(echo "$MNT_APP" | tr '\r' ' ' | tr '\n' ' ' | tr -s ' ')
    
    MNT_DEVICE=$(echo "$MNT_APP" | cut -d " " -f 8)
    MNT_POINT=$(echo "$MNT_APP" | cut -d " " -f 13)
    
    MNT_FS=$(adb shell "${CMD_HANDLER}mount 2> /dev/null | grep $MNT_DEVICE | ${CMD_HANDLER}tr -s \" \" | ${CMD_HANDLER}cut -d \" \" -f 5")
    MNT_FS=$(echo "$MNT_FS" | tr -d '\r')
    
    return 0
}

# -----------------------------------------------------------------------------
# Ищет актуальный shell и подходящие версии busybox/toybox
# -----------------------------------------------------------------------------
funCheckShell () {
    OTA_SHELL=$(adb shell 'readlink -f $0 2> /dev/null' | tr -d '\r')
    OTA_BUSYBOX=$(adb shell "readlink -f /system/bin/busybox 2> /dev/null" | tr -d '\r')
    adb shell "test -f \"$OTA_BUSYBOX\""
    if [ $? -eq 0 ] ; then
        CMD_HANDLER="$OTA_BUSYBOX "
        return 0
    fi
    
    OTA_BUSYBOX=$(adb shell "readlink -f /system/bin/toybox 2> /dev/null" | tr -d '\r')
    adb shell "test -f \"$OTA_BUSYBOX\""
    if [ $? -eq 0 ] ; then
        CMD_HANDLER="$OTA_BUSYBOX "
        # в 9 Андроиде кто-то сломал toybox, перестала работать форма <toybox ls/cat/df/...>
        adb shell "test -f \"${OTA_BUSYBOX%/*}/df\"" && adb shell "test -f \"${OTA_BUSYBOX%/*}/mount\"" && adb shell "test -f \"${OTA_BUSYBOX%/*}/sed\""
        [ $? -eq 0 ] && CMD_HANDLER=""
        return 0
    fi
    
    OTA_BUSYBOX=$(adb shell "find / -path /proc -prune -o -iname 'busybox' -print 2> /dev/null" | tr -d '\r')
    adb shell "test -f \"$OTA_BUSYBOX\""
    if [ $? -eq 0 ] ; then
        CMD_HANDLER="$OTA_BUSYBOX "
        return 0
    fi
    
    echo "ERROR: utility commands not found"
    return 1
}

# -----------------------------------------------------------------------------
# Подключаемся к указанному устройству. Таймаут принудительно установлен
# равным 1 секунде. Для локальной сети этого вполне достаточно.
# -----------------------------------------------------------------------------
funAdbConnect () {
    adb disconnect 2> /dev/null 1> /dev/null
    { timeout 1 adb connect $1:5555 2> /dev/null 1> /dev/null; } && adb root 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ] ; then 
        echo "Failed to connect"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Получаем основные сведения о подключенном устройстве.
# -----------------------------------------------------------------------------
funGetDeviceInfo () {
    RO_BRAND=$(adb shell 'getprop "ro.product.brand"' | tr -d "\r]")
    RO_MODEL=$(adb shell 'getprop "ro.product.model"' | tr -d "\r]")
    RO_RELEASE=$(adb shell 'getprop "ro.build.version.release"' | tr -d "\r]")
    RO_SDK=$(adb shell 'getprop "ro.build.version.sdk"' | tr -d "\r]")
    RO_DATE=$(adb shell 'getprop "ro.build.date.utc"' | tr -d "\r]")
    RO_DATE=$(date --u -date="@$RO_DATE" +"%d-%m-%Y %H:%M:%S")
    return 0
}

# -----------------------------------------------------------------------------
# Формирует список разделов, которые нужно смонтировать при старте
# $1 - Mount point, $2 - Device, $3 - File system
# -----------------------------------------------------------------------------
funUpdateMountList () {
    [ "$1" = "/" ] && return 0
    for mnt_point in $(echo $MOUNT_LIST) ; do
        [ "$mnt_point" = "$1" ] && return 0
    done
    MOUNT_LIST="${MOUNT_LIST:-}${MOUNT_LIST:+\n}$1"
    MOUNT_STRINGS="${MOUNT_STRINGS:-}${MOUNT_STRINGS:+\n}mount(\"$3\", \"EMMC\", \"$2\", \"$1\");"
    UNMOUNT_STRINGS="unmount(\"$1\");${UNMOUNT_STRINGS:+\n}${UNMOUNT_STRINGS:-}"
    return 0
}


# -----------------------------------------------------------------------------
# Получаем всю информацию, которая нужна для монтирования разделов с
# shell, busybox/toybox и abox.store.client
# -----------------------------------------------------------------------------
funGetFSInfo () {
    funCheckShell || return 1
    
    STORE=$(adb shell "pm list packages -f | grep abox.store.client 2> /dev/null" | tr -d '\r')
    STORE=${STORE%=*}
    STORE=${STORE#package:}
    
    if [ -z "${STORE:-""}" ] ; then
        echo "Failed to find abox.store location"
        return 1
    fi
    
    STORE_DIR=${STORE%/*}
    STORE_APP="$STORE"
    
    funCheckFS $OTA_SHELL
    funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    SHELL_MNT_POINT="$MNT_POINT"
    SHELL_MNT_DEVICE="$MNT_DEVICE"
    SHELL_MNT_FS="$MNT_FS"

    funCheckFS $OTA_BUSYBOX
    funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    BUSYBOX_MNT_POINT="$MNT_POINT"
    BUSYBOX_MNT_DEVICE="$MNT_DEVICE"
    BUSYBOX_MNT_FS="$MNT_FS"

    funCheckFS $STORE_APP
    funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    STORE_MNT_POINT="$MNT_POINT"
    STORE_MNT_DEVICE="$MNT_DEVICE"
    STORE_MNT_FS="$MNT_FS"
    
    if [ -z "$SHELL_MNT_POINT" -o -z "$BUSYBOX_MNT_POINT" -o -z "$STORE_MNT_POINT" ] ; then
        echo "ERROR: invalid mount points"
        return 1
    fi
    
    if [ "$SHELL_MNT_POINT" = "/" -o "$BUSYBOX_MNT_POINT" = "/" ] ; then
        echo "\033[0;33mWARN: some of system tools located at rootfs\033[0m"
    fi
    
    # find caches
    funCheckFS "/data"
    funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    
    STORE_CACHES=$(adb shell "find /data/ -iname '*.*dex' -print 2> /dev/null | grep abox.store.client 2> /dev/null" | tr -d '\r')
    for cache in $(echo $STORE_CACHES) ; do
        funCheckFS $cache
        funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    done
    STORE_CACHES2=$(adb shell "find /data/ -iname '*abox.store.client*' -print 2> /dev/null" | tr -d '\r')
    
    CMD_SUFILE=$(adb shell "find /system -iname 'su' -print 2> /dev/null" | tr -d '\r')
    for su_file in $(echo $CMD_SUFILE) ; do
        funCheckFS $su_file
        funUpdateMountList $MNT_POINT $MNT_DEVICE $MNT_FS
    done
    
    return 0
}

# -----------------------------------------------------------------------------
# Пробует получить версию APK из манифеста.
# Если не получилось, то использует текущую дату.
# -----------------------------------------------------------------------------
funReadApkVersion () {
    APK_VERSION=$(date +%Y%m%d)
    which aapt 2> /dev/null 1> /dev/null
    if [ $? -eq 0 ] ; then
        APK_VERSION=$(aapt dump badging ./ota-arch/app/abox.store.client/abox.store.client.apk | sed -n "s/.*versionName='\([^']*\).*/\1/p")
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Это edify скрипт, который мы используем для обновления
# -----------------------------------------------------------------------------
funMakeOTAScript () {
    echo "ui_print(\"Begin update\");"
    echo "show_progress(0.750000, 0);"
    echo "ui_print(\"Mount file vendor\");"
    echo $MOUNT_STRINGS
    echo
    echo "ui_print(\"Remove DEX caches\");"
    for dex_file in $(echo $STORE_CACHES) ; do
        echo "delete(\"$dex_file\");"
    done
    echo
    echo "ui_print(\"Unpack update script\");"
    echo "package_extract_file(\"app/update_script.sh\", \"/data/app/update_script.sh\");"
    echo "set_metadata(\"/data/app/update_script.sh\", \"uid\", 0, \"gid\", 0, \"mode\", 0750, \"capabilities\", 0x0, \"selabel\", \"u:object_r:install_recovery_exec:s0\");"
    echo "ui_print(\"Run update script\");"
    echo "run_program(\"$OTA_SHELL\", \"/data/app/update_script.sh\");"
    echo "ui_print(\"Delete update script\");"
    echo "delete(\"/data/app/update_script.sh\");"
    echo
    echo "show_progress(0.050000, 5);"
    echo "show_progress(0.200000, 10);"
    echo
    echo "ui_print(\"Unmount vendor partition\");"
    echo $UNMOUNT_STRINGS
    echo "set_progress(1.000000);"
    echo "ui_print(\"All done\");"
}

# -----------------------------------------------------------------------------
# Скрипт для обновления даты сборки
# -----------------------------------------------------------------------------
funMakeUpdateScript () {
    echo "#!/bin/sh"
    echo "path=/system/build.prop"
    echo "newver=$BUILD_DATE"
    echo "${CMD_HANDLER}sed -i -r \"s/ro.build.date.utc=.*/ro.build.date.utc=\${newver}/g\" \$path"
    echo "${CMD_HANDLER}sed -i 's/\(<package name=\"abox.store.client\".*version=\"\)\([0-9]*\)\(\".*\)/\\\1${APK_VERSION}\\\3/' /data/system/packages.xml"
    echo "${CMD_HANDLER}rm -f /data/system/package-cstats.list"
    for cache in $(echo $STORE_CACHES2) ; do
        echo "${CMD_HANDLER}rm -rf $cache"
    done
    for su_file in $(echo ${CMD_SUFILE:-""}) ; do
        echo "${CMD_HANDLER}mv -f ${su_file%/*}/su ${su_file%/*}/ssu"
    done
    echo "${CMD_HANDLER}find /data/ -iname '*abox.store.client*' -exec rm -rf {} \; 2>/dev/null"
}

# -----------------------------------------------------------------------------
# Получаем с устройства всю необходимую информацию
# -----------------------------------------------------------------------------
funCheckDevice () {
    funAdbConnect $1 || return $?
    funGetDeviceInfo
    echo "  $RO_MODEL ($RO_BRAND)"
    echo "  Android $RO_RELEASE (API: $RO_SDK)"
    echo "  $RO_DATE"
    if [ $2 -gt 0 ] ; then
        funGetFSInfo || return $?
        echo
#        echo "  $OTA_SHELL ($SHELL_MNT_POINT, $SHELL_MNT_DEVICE, $SHELL_MNT_FS)"
#        echo "  $OTA_BUSYBOX ($BUSYBOX_MNT_POINT, $BUSYBOX_MNT_DEVICE, $BUSYBOX_MNT_FS)"
#        echo "  $STORE_APP ($STORE_MNT_POINT, $STORE_MNT_DEVICE, $STORE_MNT_FS)"
#        echo
        echo "  Shell: $OTA_SHELL"
        echo "  Binutils: $OTA_BUSYBOX"
        echo "  abox.store: $STORE_APP"
        echo
    fi
    adb disconnect 2> /dev/null 1> /dev/null
}

# -----------------------------------------------------------------------------
# Получаем список устройств в локальной сети, на которых открыт 5555 порт
# -----------------------------------------------------------------------------
funScanSubnet () {
    [ -z "$ADBSCAN" ] && return 1
    echo "Search for active devices..."
    ADDR_LIST=$($ADBSCAN -b)
    if [ ${#ADDR_LIST} -lt 7 ] ; then
        echo "No active devices found"
        return 2
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Если пользователь явно не указал IP-адрес устройства, то функция
# дает выбрать из списка активных устройств в локальной сети.
# (в POSIX shell нет оператора select, поэтому приходится идти длинным путем)
# -----------------------------------------------------------------------------
funSelectAddr () {
    DEVICE_ADDR=""
    funScanSubnet || return 1
    echo "Please, select device:"
    Count=1
    for addr in $ADDR_LIST ; do
        echo "  $Count) $addr"
        Count=$((Count+1))
    done
    while true ; do
        read idx
        echo "\033[1A\033[K\033[1A" # после ввода остаемся на той же строке
        case ${idx:-""} in
            *[!0-9]*|"") continue ;;
        esac
        if [ "$idx" -gt 0 -a "$idx" -lt $Count ] ; then
            break
        fi
    done
    Count=1
    for addr in $ADDR_LIST ; do
        [ $Count -eq $idx ] && break
        Count=$((Count+1))
    done
    DEVICE_ADDR=$addr
}


# =============================================================================
# Начало основной части скрипта
# =============================================================================

OPT_MODE=${1:-'help'}
DEVICE_ADDR=${2:-""}

case $OPT_MODE in
    # показываем краткую информацию об устройстве: модель, версия Андроид и дату сборки.
    # если не указать IP адрес устройства, то скрипт перейдет в интерактивный режим
    "info" )
    if [ -z $DEVICE_ADDR ] ; then
        if [ -z "$ADBSCAN" ] ; then
            funShowUsage
            return 0
        fi
        funSelectAddr || return 1
    fi
    ;;

    # для этих двух режимов требуется указывать IP адрес
    "script" | "arch" )
    if [ -z $DEVICE_ADDR ] ; then
        funShowUsage
        return 0
    fi
    ;;

    # если есть возможность, то покажем краткую информацию обо всех
    # доступных в локальной сети устройствах
    "scan" )
    if [ -z "$ADBSCAN" ] ; then
        funShowUsage
        return 0
    fi
    echo "Search for active devices..."
    ADDR_LIST=$($ADBSCAN -b)
    for addr in $ADDR_LIST; do
        echo "\n\033[0;32mDevice $addr:\033[0m" # выделяем цветом заголовок
        funCheckDevice $addr 0
    done
    echo
    exit 0
    ;;
    
    # если параметры заданы некорретно, покажем краткую справку
    * )
    funShowUsage
    exit 0
    ;;
esac

MOUNT_LIST=""

echo "\nDevice $DEVICE_ADDR:"
funCheckDevice $DEVICE_ADDR 1 || return $?
[ $OPT_MODE = "info" ] && return 0

# если у нас есть третий параметр - дата, 
# проверяем корректность и пробуем ее распарсить
ARG_DATE=${3:-"@1605052800"}
case $ARG_DATE in
    *[' ']*) ARG_DATE="\"$ARG_DATE\"" ;;
esac
BUILD_DATE=$(date -u --date="$ARG_DATE" +"%s" )
if [ $? -gt 0 ] ; then
    echo "Invalid date: $3"
    return 1
fi

STR_DATE=$(date -u -r $BUILD_DATE +"%d-%m-%Y")
STR_BRAND=$(echo $RO_BRAND | tr ' ' '_') # в имени бренда не должно быть пробелов
OTA_FILE_NAME="ota_${STR_BRAND}_${STR_DATE}.zip"

# предупреждаем, если указана дата раньше 2010-01-01 либо позже 2030-01-01
if [ $BUILD_DATE -lt 1262304000 -o $BUILD_DATE -gt 1893456000 ] ; then
    echo "\033[0;33mWARN: build date set to ${STR_DATE}\033[0m"
fi

# версия стора по умолчанию задана в начале скрипта
# funReadApkVersion
echo "  APK Version = ${APK_VERSION}"
echo "  ro.build.date = ${STR_DATE}"
for su_file in $(echo $CMD_SUFILE) ; do
    echo "  Root path: ${su_file%/*}"
done

case $OPT_MODE in
    # показываем на экране подготовленные скрипты,
    # физически они никуда не сохраняются
    "script" )
    echo
    echo "\033[0;36m--== OTA script ==--\033[0m"
    funMakeOTAScript
    echo "\033[0;36m--== END ==--\033[0m"
    echo
    echo "\033[0;36m--== UPDATE script ==--\033[0m"
    funMakeUpdateScript
    echo "\033[0;36m--== END ==--\033[0m"
    echo
    ;;
    
    # готовим скрипты и пакуем их в архив с abox.store.client
    # (для корректной работы нужны установленный zip и каталог ota-arch)
    "arch" )
    which zip 2> /dev/null 1> /dev/null
    if [ $? -ne 0 ] ; then
        echo "Can't find <zip> program. Please, install it."
        return 1
    fi
    if [ ! -d "./ota-arch" ] ; then
        echo "Can't find <ota-arch> directory."
        return 1
    fi
    funMakeOTAScript > ./ota-arch/META-INF/com/google/android/updater-script
    if [ $? -ne 0 ] ; then
        echo "Error while writing <updater-script>"
        return 1
    fi
    funMakeUpdateScript > ./ota-arch/app/update_script.sh
    if [ $? -ne 0 ] ; then
        echo "Error while writing <update_script.sh>"
        return 1
    fi
    cd ./ota-arch
    zip -r -q "../$OTA_FILE_NAME" ./*
    if [ $? -eq 0 ] ; then
        echo "File <$OTA_FILE_NAME> created."
        echo
    else
        echo "Error while creating zip archive."
        echo
    fi
    cd ..
    ;;
    
    *) echo "!Script logic is broken!" ;;
esac

return 0
