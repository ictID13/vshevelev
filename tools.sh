#!/usr/bin/env bash

########################################

K_GET_IP="--get_ip"
K_CONNECT="--connect"
K_DISCONNECT="--disconnect"
K_CONNECT2ALL_SEND_BROADCAST="--connect2all_send_broadcast"
K_GETPROP="--getprop"
K_INSTALL="--install"
K_INSTALL_PAK="--install_pack_apk"
K_LOGCAT="--get_logcat"
K_OPEN_FACT="--open_factory"
K_UNINST="--uninstall"
K_UNINST_PAK="--uninstall_pack_apk"
K_UNINST_DIFF="--uninstall_diff_apk"
K_SEND="--send_broadcast_store_client"
K_STOP_APP="--stop_app"
K_GET_NAME="--get_app_name"
K_GET_VERS="--get_app_name_version"
K_DIFF_VERSION="--check_apps_version_vs"
K_FIND="--find_on_android"
K_MONKEY="--monkey_test"
K_CLEAR_DATA="--clear_data"
K_RFAV="--readfromapkversion"
K_HELP="--help"

ALL_KEYWORDS=( "${K_OPEN_FACT}" "${K_INSTALL}" "${K_RFAV}" "${K_GETPROP}" "${K_GET_IP}" "${K_MONKEY}" "${K_CONNECT}" "${K_DISCONNECT}" "${K_CONNECT2ALL_SEND_BROADCAST}" "${K_INSTALL_PAK}" "${K_LOGCAT}" "${K_UNINST}" "${K_UNINST_PAK}" "${K_UNINST_DIFF}" "${K_SEND}" "${K_STOP_APP}" "${K_GET_NAME}" "${K_GET_VERS}" "${K_DIFF_VERSION}" "${K_CLEAR_DATA}" "${K_FIND}" "${K_HELP}")

###################Стартовые переменные#####################
TOOL=~/.tool/
WHITELIST=(${TOOL}list_ip.txt)
IP=$(cat ${WHITELIST})

WHITEEX=(${TOOL}ip_ex.txt)
IPX=$(cat ${WHITEEX})

MODULES_INSTALL=(${TOOL}modules.install)
MODULES_UNINSTALL=(${TOOL}modules.uninstall)

APKFILES=$(cat ${MODULES_INSTALL})
TEMP_DIFF_NEW_OLD=(${TOOL}app_diff_new_old.txt)

FIND=su
PKG=store
ACTIVITY=.ui.MainActivity
APPDEF=(${TOOL}app_stock.txt)
APPCUR=(${TOOL}app_updated.txt)

###################Проверки темповых файлов#####################
# Проверка наличия папки, создание
  mkdir -p ~/.tool

# Проверка файла, создание
  if ! [  -f  ${TOOL}modules.install ]; then
    touch ${TOOL}modules.install
  fi

# Проверка файла, создание
if ! [  -f  ${TOOL}modules.uninstall ]; then
    touch ${TOOL}modules.uninstall
  fi

# Проверка файла + создание ip лист
  if ! [  -f  ${TOOL}list_ip.txt ]; then
    touch ${TOOL}list_ip.txt
  fi

#####################################################################

showHelp() {
cat << EOF
Usage: $(basename "$0") <commands>
Simple cli helper for android client.
Default: build, install apk and launch main activity.
  ${K_GET_IP}                      scan network to open port 5555
  ${K_CONNECT}                     simple adb connect
  ${K_DISCONNECT}                  simple disconnect
  ${K_CONNECT2ALL_SEND_BROADCAST}  connect to ip-list and send broadcast
  ${K_GETPROP}                     get prop list
  ${K_INSTALL}                     adb install
  ${K_INSTALL_PAK}            install pack apk from current directory
  ${K_LOGCAT}                  logcat
  ${K_OPEN_FACT}                open factory menu
  ${K_UNINST}                   adb uninstall
  ${K_UNINST_PAK}          uninstall pack apk
  ${K_UNINST_DIFF}          uninstall diff version app
  ${K_SEND}
  ${K_STOP_APP}                    force-stop app
  ${K_GET_NAME}                get app name
  ${K_GET_VERS}        get app version
  ${K_DIFF_VERSION}       diff version
  ${K_FIND}             find on android device
  ${K_MONKEY}                 run monkey monkey test
  ${K_CLEAR_DATA}                  pm clear
  ${K_RFAV}          read name app from apk
  ${K_HELP}            Show this help and exit
EOF
}

tab(){
echo "===================================================================================================="
}

get_ip(){
  echo -n "В какой сети искать?192.168.0.100-254     :"
    read RANGE
  echo -n "Порт?\"5555\"   :"
    read PORT
# nmap -p ${PORT:="5555"} -n ${RANGE:=192.168.0.100-254} --open |grep report |ssed 's/Nmap scan report for //' > ${WHITELIST}
nmap -p ${PORT:="5555"} -n ${RANGE:=192.168.0.100-254} --open -oG - | awk '/Up$/{print $2}' > ${WHITELIST}
  echo "Список ip адресов с открытым портом ${PORT:="5555"}"
cat ${WHITELIST}
}

#подключение adb connect
connect(){
#   echo "Try connect to $(head -n 1 ${WHITELIST}|tail -n 1)"
    echo -n "connect to ip?192.168.0.100    :"
    read -e IP
#   timeout 1 adb connect $(head -n 1 ${WHITELIST}|tail -n 1):5555 2> /dev/null 1> /dev/null
    timeout 1 adb connect ${IP:=192.168.0.100}:5555 #2> /dev/null 1> /dev/null
    if [ $? -ne 0 ] ; then
        echo "Failed to connect"
        return 1
    fi
    echo "Success"
    return 0
}

#подключение к ТВ по списку, отсылка broadcast, отключение
connect2all_send_broadcast(){
    for IPS in ${IP}; do
            disconnect
            tab
            echo "Try connect to ${IPS}"
            timeout 3 adb connect ${IPS}:5555  2> /dev/null 1> /dev/null
            if [ $? -ne 0 ] ; then
        echo "Failed to connect"
    fi
    echo "Success"
#    return 0
getprop
sleep 1
get_app_name_version  |grep abox.store.client
#echo > ${MODULES_UNINSTALL}
#get_app_name >> ${MODULES_UNINSTALL}
#uninstall_pack_apk

    done
  disconnect
    }


#Установка отдельных apk
install(){
  adb install -r /Users/Viktor/Documents/PROJECTS/STORE.CLIENT/APP/abox.store.client_20191226.apk
sleep 1
  disconnect
}


#Установка списка приложений
install_pack_apk(){
    cat /dev/null >|${MODULES_INSTALL}
    ls -1 *.apk >> ${MODULES_INSTALL}

# for INP in  $(ls -f *.tar.gz );do
    for APK in $(cat ${MODULES_INSTALL}); do
            tab
            echo "Installing  ${APK}"
            adb install -r ${APK} # 2> /dev/null 1> /dev/null
            if [ $? -ne 0 ] ; then
        echo "Failed to install ${APK}"
    fi

    done
    }

#получение списка getprop
getprop(){
echo "Получение getprop:"
adb shell getprop |grep -E "(sys.wildred.hw_id|sys.wildred.brand|ro.product.brand|ro.product.device|ro.product.model|sys.wildred.version|ro.build.version.min_supported_target_sdk|ro.build.version.sdk|ro.build.date.utc|ro.build.date|ro.sf.lcd_density|qemu.sf.lcd_density|vendor.display-size|smarttv.current.apk.activity|smarttv.current.apk.package|ro.main.version|ro.main.version.date)"
# > ~/.tool/${IPS}.txt
}


#Monkey test для выбранного приложения
monkey_test(){
echo  ho -n "По какому приложению будем проводить monkey-тест?default(com.family.atlas.launcher) :"
  read PACKAGE
echo -n "Задержка между событиями в ms ?default(100ms) :"
  read THROTTLE
echo -n "Количество событий?default(1000) :"
  read EVENT
adb shell monkey -p ${PACKAGE:=com.family.atlas.launcher} --pct-touch 0 --pct-motion 20 --pct-nav 20 --pct-majornav 10 --pct-syskeys 40 --pct-appswitch 10 --ignore-security-exceptions --throttle ${THROTTLE:=100}  -vv ${EVENT:=1000}
        adb shell kill $(adb shell pidof com.android.commands.monkey)
}

#Остановка приложения abox.store
stop_app(){
    echo "Остановка abox.store.client"
    adb shell am force-stop ${PKG:=abox.store.client}
    }

restart_app() {
    stop_app
    launch_activity
}

#Установка prop
setprop(){
echo "Установка prop "
  adb shell setprop persist.sys.registered 1
  adb shell setprop persist.sys.licensed 1

}


#Удаление определенного приложения
uninstall(){
    local IS_SYSTEM=$(adb shell /system/bin/busybox id -u)
    echo "Uninstall package"
    if [ ${IS_SYSTEM} != 0 ]; then
        adb uninstall ${}
    else
           echo "Удаление apk с правами root"
           adb root
           adb remount
           adb shell pm uninstall -k  ${}
           adb unroot
    fi
    }


# Удаление пакета diff новый/старый
uninstall_diff_apk(){
    echo "Удаление списка приложений  от обновленного к предыдущему состоянию:"
      diff -E -b -B -w  ${APPCUR} ${APPDEF} | grep "<" | sed -e 's/^[ <]*//' > ${TEMP_DIFF_NEW_OLD}
        for APK in $(cat ${TEMP_DIFF_NEW_OLD}); do
          echo "Uninstalling apk ${APK}"
            adb uninstall ${APK}
        done
}


#Удаление списка приложений
uninstall_pack_apk(){
    for APK in $(cat ${MODULES_UNINSTALL}); do
            tab
            echo "Uninstalling apk ${APK}"
            adb shell pm uninstall -k ${APK} #2>/dev/null 1>/dev/null
            if [ $? -ne 0 ] ; then
        echo "Failed to uninstall ${APK}"
    fi

    done
}


get_app_name() {
#    echo "Получение списка имен пакетов"
    CMD='adb shell "pm list packages -f" | sed -e "s/==//"'
    PACKAGES=$(eval ${CMD} | cut -f 2 -d "=")
#    echo  ${PACKAGES}
    if [ ${#PACKAGES[@]} == 0 ]; then
	    echo "No packages found"
	    exit 0
    fi
    for PA in "${PACKAGES[@]}"; do
	echo -e  "${PA}\n"

    done
    }


pull_file() {
  echo "pull_apk"

}

push_file() {
  echo "push_apk"
}

send_exec(){
  echo "exec_script"
}

get_logcat(){
    echo -n "Show logcat | grep by word?:"
    read FD
    adb shell logcat |  grep "${FD}"
    }

launch_activity() {
    adb_all shell am start -n "$PKG/$ACTIVITY" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
}
tree() {
    adb_all shell "ls -lahR /data/data/${PKG}"
}
########################################
prefs() {
    adb_all shell "cat /data/data/${PKG}/shared_prefs/*.xml"
}



#Получение установленных приложений и их версий с записью в файл
get_app_name_version() {
  echo "Получение списка пакетов и их версий"
#    android_get_installed_packages.sh > ${APPDEF}
#
    CMD='adb shell "pm list packages -f" | ssed -e "s/==//"'
    PACKAGES=($(eval ${CMD} | cut -f 2 -d "="))

    if [ ${#PACKAGES[@]} == 0 ]; then
	    echo "No packages found"
#	    exit 0
    fi

    echo "Found packages: ${#PACKAGES[@]}"

    for P in "${PACKAGES[@]}"; do
	    NAME=$(echo "${P//[$'\t\r\n ']}")
	    VERSIONS=($(adb shell dumpsys package $NAME | grep -i versionName | awk -F"=" '{print $2}'))
		echo "$NAME $VERSIONS"
    done
    }


launch_activity(){
    adb shell am start -n "$PKG/$ACTIVITY" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
    }


#Сравнение списков приложений. Текущий список  - Стоковый список и запист различий в файл foundit.txt
check_apps_version_vs(){
    echo "Сравнение файлов до и после обновления"
#Без версии пакетов
#   diff -E -b -B -w  ${APPCUR} ${APPDEF} | grep "<" | sed -e 's/^[ <]*//' > ${TEMP_DIFF_NEW_OLD}
#С версиями пакетов
    diff -E -b -B -w  ${APPCUR} ${APPDEF} | grep "<" || sed -e 's/^[ <]*//' > ${TEMP_DIFF_NEW_OLD}
    cat ${TEMP_DIFF_NEW_OLD}.txt
    }

#Отправка broadcast'а для того что бы дернуть сервис  abox.store.client
send_broadcast_store_client(){
      echo "Broadcast for abox.store.client already send"
      adb shell am broadcast -a abox.store.client.ACTION_START -n abox.store.client/.receiver.StoreBroadcastReceiver
      }
open_factory(){
tab
echo "Последовательный перебор всех  вариантов вызова factory_menu "
tab
echo "send HiKeen(RTK2851/RTK2842) SOURCE>2580"
  adb shell am start -n 'com.hikeen.factorymenu/com.hikeen.factorymenu.FactoryMenuActivity'  2> /dev/null 1> /dev/null
  sleep 1
echo ""
echo "send CVTE(MTK55xx/SK506/SK706) HOME.SOURCE>ATV>MENU>1147"
  adb shell am startservice -n com.cvte.fac.menu/com.cvte.fac.menu.app.TvMenuWindowManagerService --es com.cvte.fac.menu.commmand com.cvte.fac.menu.commmand.factory_menu  2> /dev/null 1> /dev/null
  sleep 1
echo ""
echo "send KTC(6681) SOURCE>ATV>MENU>8202"
  adb shell am start -n kgzn.factorymenu.ui/mediatek.tvsetting.factory.ui.kgznfactorymenu.FactoryMenuActivity  2> /dev/null 1> /dev/null
  sleep 1
tab
}


#Очистка кэша приложения
clear_data() {
  for CLP in $(cat ${MODULES_UNINSTALL});do
  adb shell pm clear "${CLP}"
  done
  }

#Чтение версии приложения из apk
readfromapkversion() {
#  APK_VERSION=$(date +%Y%m%d)
 cat /dev/null >|${MODULES_UNINSTALL}
for INP in  $(ls -f *.apk );do
#     APK_VERSION=$(aapt dump badging ${INP} | ssed -n "s/.*versionName='\([^']*\).*/\1/p")
      APK_VERSION=$(aapt dump badging ${INP} | ssed -n "s/.*package: name='\([^']*\).*/\1/p")

      echo "${APK_VERSION}" >> ${MODULES_UNINSTALL}
      echo " ${INP} : ${APK_VERSION}"
done
}

find_on_android() {
    echo -n "Поиск на устройстве по заданному слову через busybox(*.apk)     :"
    read FD
#    adb shell /system/bin/busybox find / -name "*${FD:=*.apk}*" |grep -v "Permission denied"
    adb shell find / -name "*${FD:=*.apk}*" 2>/dev/null
  }

disconnect() {
    adb disconnect 2> /dev/null #1> /dev/null
#    echo "Disconnect "
    }


#-------------------------------MAIN-----------------------------------------------------


#if [[ "${@}" == *"${K_HELP}"* ]]; then
#	showHelp
#	exit 0
#fi
clear
tab
echo -n "Start MAIN Script : "
date
tab
echo ""
echo ""


for arg in "$@"; do
	  case ${arg} in
	    ${K_GET_IP})
	         get_ip
	         shift 1
	          ;;
	    ${K_CONNECT})
	          connect
	    	    shift 1
	    	    ;;
	    ${K_DISCONNECT})
	          disconnect
	          shift 1
	          ;;
      ${K_CONNECT2ALL_SEND_BROADCAST})
            connect2all_send_broadcast
            shift 1
            ;;
      ${K_UNINST})
            uninstall
            shift 1
            ;;
      ${K_INSTALL})
          install
          shift 1
          ;;
      ${K_INSTALL_PAK})
            install_pack_apk
            shift 1
            ;;
      ${K_UNINST_PAK})
            uninstall_pack_apk
            shift 1
            ;;
      ${K_SEND})
            send_broadcast_store_client
            shift 1
            ;;
      ${K_GETPROP})
            getprop
            shift 1
            ;;
      ${K_STOP_APP})
            stop_app
            shift 1
            ;;
      ${K_LOGCAT})
            get_logcat
            shift 1
            ;;
      ${K_GET_NAME})
            get_app_name
            shift 1
            ;;
      ${K_GET_VERS})
            get_app_name_version
            shift 1
            ;;
      ${K_RFAV})
            readfromapkversion
            shift 1
            ;;
      ${K_OPEN_FACT})
            open_factory
            shift 1
            ;;
      ${K_DIFF_VERSION})
            check_apps_version_vs
            shift 1
            ;;
      ${K_CLEAR_DATA})
            clear_data
            shift 1
            ;;
      ${K_MONKEY})
            monkey_test
            shift 1
            ;;
      ${K_FIND})
            find_on_android
            shift 1
            ;;
      ${K_HELP})
	          showHelp
	          exit 0
	          ;;
	    *)
#	      >&2
	      echo "Unknown argument: $arg"
	      exit 1
	      ;;
	  esac
done






