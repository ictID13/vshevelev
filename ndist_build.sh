#!/usr/bin/env bash

########################################
K_BUILDALLTAR="--build_tar"
K_BUILDALLTARBYLIST="--build_tar_list"
K_BUILDALLZIP="--build_zip"
K_BUILDALLZIPBYLIST="--build_zip_list"
K_CHECKALLTARINDIR="--check"
K_BUILDALLMODULE="--build_module"
K_CLEARDATA="--clear"
K_EXTRACT_TAR="--extract_tar"
K_HELP="--help"
ALL_KEYWORDS=("${K_EXTRACT_TAR}" "${K_BUILDALLMODULE}" "${K_BUILDALLTAR}" "${K_BUILDALLTARBYLIST}" "${K_BUILDALLZIP}" "${K_BUILDALLZIPBYLIST}" "${K_CHECKALLTARINDIR}" "${K_HELP}")

# Проверка наличия папки, создание
if ! [  -d  ~/.tool ]; then
  mkdir ~/.tool
fi

# Проверка файла, создание
if ! [  -f  ~/.tool/build.log ]; then
    touch ~/.tool/build.log
fi

DIR1="/Volumes/test/abox/"
DIR2="~/.tool/"
DIR3="/Volumes/test/abox/output/"
DIR4=(${DIR3}Module_"`date +"%d-%m-%Y"`")

#help к утилите
showHelp(){
cat << EOF
Usage: $(basename "$0") <commands>
Simple cli helper for android client.
Default: build, install apk and launch main activity.
  ${K_BUILDALLTAR}
  ${K_BUILDALLTARBYLIST}
  ${K_BUILDALLZIP}
  ${K_BUILDALLZIPBYLIST}
  ${K_CHECKALLTARINDIR}
  ${K_HELP}            Show this help and exit
EOF
}


#сборка всех tarboll по конфигам
build_tar(){
  cat /dev/null > ${DIR2}build.log
  pwd >> ${DIR2}build.log
  cd ${DIR1}

  for CONF in $(./ndist conf); do
    echo ${CONF}
    ./ndist build tar ${CONF}
    echo "Build tar.gz ${CONF}"  >> ${DIR2}build.log
done
}


#сборка указанного  модуля по заданному списку
build_tar_list(){
        echo "пока не работает"
}


#сборка  модуля для всех конфигов
build_module(){
  cat /dev/null > ~/.tool/build.log
  pwd > ~/.tool/build.log
    cd ${DIR1}
  echo -n "Какой модуль будем собирать?:"
  read -e MODULE
  echo ${DIR4}
  mkdir -p ${DIR4}

  for CONF in $(./ndist conf); do
    ./ndist build --module=${MODULE} ${CONF} zip
    unzip -q -o ${DIR3}*.zip -d ${DIR3}
    rm -rf ${DIR3}*.zip
    zip ${DIR4}/${MODULE}.zip ${DIR3}*.apk
    rm -rf ${DIR3}*.apk
    pwd >> ~/.tool/build.log
    echo "Build zip ${CONF}" >> ~/.tool/build.log
done
}


# добавление нужного модуля в все конфигурации
build_module(){
  cat /dev/null > ~/.tool/build.log
  pwd > ~/.tool/build.log
        cd ${DIR1}
 echo -n "Какой модуль будем собирать?:"
 read -e MODULE
DIR4=(${DIR3}Module_"`date +"%d-%m-%Y"`")
echo ${DIR4}
        mkdir -p ${DIR4}

        for CONF in $(./ndist conf); do
          ./ndist build --module=${MODULE} ${CONF} zip
          unzip -q -o ${DIR3}*.zip -d ${DIR3}
          rm -rf ${DIR3}*.zip
          zip ${DIR4}/${MODULE}.zip ${DIR3}*.apk
          rm -rf ${DIR3}*.apk
          pwd > ~/.tool/build.log
          echo "Build zip ${CONF}"  >> ~/.tool/build.log
done
}


#сборка  всех zip по всем конфигам
build_zip(){
  cat /dev/null > ~/.tool/build.log
  pwd > ~/.tool/build.log
  cd ${DIR1}

  for CONF in $(./ndist conf); do
    echo ${CONF}
#   ./ndist build zip ${CONF}
    pwd > ~/.tool/build.log
    echo "Build zip ${CONF}"  >> ~/.tool/build.log
done
}


#сборка  zip по заданным конфигам в файле
build_all_zip_list(){
  for CONF in @2; do
    echo ${CONF}
    ./ndist build zip ${CONF}
done
}


#очистка  всех собранных апк
clear(){
    echo "Clear all data gradlew"
    cd ${DIR1}
        ./gradlew clean
}


#Проверка архивов на целостность
check(){
  pwd >> ~/.tool/build.log

  for INP in  $(ls -f *.tar.gz );do
#        for INP in  $(cat /Volumes/test/2.7.3/list.txt);do
         gtar -xf $INP > /dev/null; echo "Checking tar ${INP}:$?" >> ~/.tool/build.log
         echo "Checking tar ${INP}:$?"
done
}


extract_tar(){
  pwd >> ~/.tool/build.log

  for INP in  $(ls -f *.tar.gz );do
    TAR=(${INP/%???????/})
    mkdir -p /Volumes/test/2.7.7/${TAR}
#   for INP in  $(cat /Volumes/test/2.7.3/list.txt);do
    echo -e "\e[31mРазархивируется ${INP}\e[0m"
    tar -C /Volumes/test/2.7.7/${TAR} -xvf ${INP}
done
}


#-------------------------------MAIN-----------------------------------------------------
if [[ "${@}" == *"${K_HELP}"* ]]; then
  showHelp
  exit 0
fi

for arg in "$@"; do
          case ${arg} in
        ${K_BUILDALLTAR})
        build_tar
        shift 1
        ;;
        ${K_EXTRACT_TAR})
        extract_tar
        shift 1
        ;;
        ${K_BUILDALLTARBYLIST})
        build_tar_list
        shift 1
        ;;
        ${K_BUILDALLZIP})
        build_zip
        shift 1
        ;;
        ${K_BUILDALLZIPBYLIST})
        build_all_zip_list
                ;;
        ${K_CHECKALLTARINDIR})
        check
                ;;
        ${K_BUILDALLMODULE})
        build_module
                ;;
        ${K_CLEARDATA})
        clear
            ;;
            *)
#             >&2
              echo "Unknown argument: $arg"
              exit 1
              ;;
          esac
        done

