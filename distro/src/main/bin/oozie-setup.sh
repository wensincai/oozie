#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

function printUsage() {
  echo
  echo " Usage  : oozie-setup.sh <Command and OPTIONS>"
  echo "          prepare-war [-d directory] [-secure] (-d identifies an alternative directory for processing jars"
  echo "                                                -secure will configure the war file to use HTTPS (SSL))"
  echo "          sharelib create -fs FS_URI [-locallib SHARED_LIBRARY] [-concurrency CONCURRENCY]"
  echo "                                                                (create sharelib for oozie,"
  echo "                                                                FS_URI is the fs.default.name"
  echo "                                                                for hdfs uri; SHARED_LIBRARY, path to the"
  echo "                                                                Oozie sharelib to install, it can be a tarball"
  echo "                                                                or an expanded version of it. If omitted,"
  echo "                                                                the Oozie sharelib tarball from the Oozie"
  echo "                                                                installation directory will be used."
  echo "                                                                CONCURRENCY is a number of threads to be used"
  echo "                                                                for copy operations."
  echo "                                                                By default 1 thread will be used)"
  echo "                                                                (action fails if sharelib is already installed"
  echo "                                                                in HDFS)"
  echo "          sharelib upgrade -fs FS_URI [-locallib SHARED_LIBRARY] ([deprecated][use create command to create new version]"
  echo "                                                                  upgrade existing sharelib, fails if there"
  echo "                                                                  is no existing sharelib installed in HDFS)"
  echo "          db create|upgrade|postupgrade -run [-sqlfile <FILE>] (create, upgrade or postupgrade oozie db with an"
  echo "                                                                optional sql File)"
  echo "          export <file>                                         exports the oozie database to the specified"
  echo "                                                                file in zip format"
  echo "          import <file>                                         imports the oozie database from the zip file"
  echo "                                                                created by export"
  echo "          (without options prints this usage information)"
  echo
  echo " EXTJS can be downloaded from http://www.extjs.com/learn/Ext_Version_Archives"
  echo
}

#Creating temporary directory
function prepare() {
  tmpDir=/tmp/oozie-war-packing-$$
  rm -rf ${tmpDir}
  mkdir ${tmpDir}
  tmpWarDir=${tmpDir}/oozie-war
  mkdir ${tmpWarDir}
  checkExec "creating staging directory ${tmpDir}"
}

#cleans up temporary directory
function cleanUp() {
  if [ ! "${tmpDir}" = "" ]; then
    rm -rf ${tmpDir}
    checkExec "deleting staging directory ${tmpDir}"
  fi
}

#check execution of command
function checkExec() {
  if [ $? -ne 0 ]
  then
    echo
    echo "Failed: $1"
    cleanup_and_exit
  fi
}

#check that a file/path exists
function checkFileExists() {
  if [ ! -e ${1} ]; then
    echo
    echo "File/Dir does no exist: ${1}"
    cleanup_and_exit
  fi
}

#check that a file/path does not exist
function checkFileDoesNotExist() {
  if [ -e ${1} ]; then
    echo
    echo "File/Dir already exists: ${1}"
    cleanup_and_exit
  fi
}


# resolve links - $0 may be a softlink
PRG="${0}"

while [ -h "${PRG}" ]; do
  ls=`ls -ld "${PRG}"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "${PRG}"`/"$link"
  fi
done

BASEDIR=`dirname ${PRG}`
BASEDIR=`cd ${BASEDIR}/..;pwd`

JETTY_DIR=${BASEDIR}/embedded-oozie-server
JETTY_WEBAPP_DIR=${JETTY_DIR}/webapp
JETTY_LIB_DIR=${JETTY_WEBAPP_DIR}/WEB-INF/lib/

source ${BASEDIR}/bin/oozie-sys.sh -silent

addExtjs=""
addHadoopJars=""
additionalDir=""
extjsHome=""
jarsPath=""
prepareWar=""
inputWar="${OOZIE_HOME}/oozie.war"
outputWar="${CATALINA_BASE}/webapps/oozie.war"
outputWarExpanded="${CATALINA_BASE}/webapps/oozie"
secure=""
secureConfigsDir="${CATALINA_BASE}/conf/ssl"

while [ $# -gt 0 ]
do
  if [ "$1" = "sharelib" ] || [ "$1" = "db" ] || [ "$1" = "export" ] || [ "$1" = "import" ]; then
    OOZIE_OPTS="-Doozie.home.dir=${OOZIE_HOME}";
    OOZIE_OPTS="${OOZIE_OPTS} -Doozie.config.dir=${OOZIE_CONFIG}";
    OOZIE_OPTS="${OOZIE_OPTS} -Doozie.log.dir=${OOZIE_LOG}";
    OOZIE_OPTS="${OOZIE_OPTS} -Doozie.data.dir=${OOZIE_DATA}";
    OOZIE_OPTS="${OOZIE_OPTS} -Dderby.stream.error.file=${OOZIE_LOG}/derby.log"

    #Create lib directory from war if lib doesn't exist
    if [ ! -d "${BASEDIR}/lib" ]; then
      mkdir ${BASEDIR}/lib

      if [ "${OOZIE_USE_TOMCAT}" = "1" ]; then
        unzip ${BASEDIR}/oozie.war WEB-INF/lib/*.jar -d ${BASEDIR}/lib > /dev/null
        mv ${BASEDIR}/lib/WEB-INF/lib/*.jar ${BASEDIR}/lib/
        rmdir ${BASEDIR}/lib/WEB-INF/lib
        rmdir ${BASEDIR}/lib/WEB-INF
      else
        cp ${JETTY_LIB_DIR}/*  ${BASEDIR}/lib
      fi

    fi

    OOZIECPPATH=""
    OOZIECPPATH=${BASEDIR}/lib/'*':${BASEDIR}/libtools/'*':${BASEDIR}/libext/'*'

    if test -z ${JAVA_HOME}; then
      JAVA_BIN=java
    else
      JAVA_BIN=${JAVA_HOME}/bin/java
    fi

    if [ "$1" = "sharelib" ]; then
      shift
      ${JAVA_BIN} ${OOZIE_OPTS} -cp ${OOZIECPPATH} org.apache.oozie.tools.OozieSharelibCLI "${@}"
    elif [ "$1" = "db" ]; then
      shift
      ${JAVA_BIN} ${OOZIE_OPTS} -cp ${OOZIECPPATH} org.apache.oozie.tools.OozieDBCLI "${@}"
    elif [ "$1" = "export" ]; then
      ${JAVA_BIN} ${OOZIE_OPTS} -cp ${OOZIECPPATH} org.apache.oozie.tools.OozieDBExportCLI "${@}"
    elif [ "$1" = "import" ]; then
      ${JAVA_BIN} ${OOZIE_OPTS} -cp ${OOZIECPPATH} org.apache.oozie.tools.OozieDBImportCLI "${@}"
    fi
    exit $?
  elif [ "$1" = "-secure" ]; then
    shift
    secure=true
  elif [ "$1" = "-d" ]; then
    shift
    additionalDir=$1
  elif [ "$1" = "prepare-war" ]; then
    prepareWar=true
  else
    printUsage
    exit -1
  fi
  shift
done

if [ -e "${CATALINA_PID}" -a "${OOZIE_USE_TOMCAT}" = "1" ]; then
  echo
  echo "ERROR: Stop Oozie first"
  echo
  exit -1
fi

echo


log_ready_to_start() {
  echo

  echo "INFO: Oozie is ready to be started"

  echo
}

check_extjs() {
  if [ "${addExtjs}" = "true" ]; then
    checkFileExists ${extjsHome}
  else
    echo "INFO: Oozie webconsole disabled, ExtJS library not specified"
  fi
}

# Check if it is necessary to add extension JARs and ExtJS
check_adding_extensions() {
  libext=${OOZIE_HOME}/libext
  if [ "${additionalDir}" != "" ]; then
    libext=${additionalDir}
  fi

  if [ -d "${libext}" ]; then
    if [ `ls ${libext} | grep \.jar\$ | wc -c` != 0 ]; then
      for i in "${libext}/"*.jar; do
        echo "INFO: Adding extension: $i"
        jarsPath="${jarsPath}:$i"
        addJars="true"
      done
    fi
    if [ -f "${libext}/ext-2.2.zip" ]; then
      extjsHome=${libext}/ext-2.2.zip
      addExtjs=true
    fi
  fi
}

cleanup_and_exit() {
  echo
  cleanUp
  exit -1
}

prepare_jetty() {
  check_adding_extensions
  check_extjs

  if [ "${addExtjs}" = "true" -a ! -e ${JETTY_WEBAPP_DIR}/ext-2.2 ]; then
     unzip ${extjsHome} -d ${JETTY_WEBAPP_DIR}
    checkExec "Extracting ExtJS to ${JETTY_WEBAPP_DIR}/"
  elif [ "${addExtjs}" = "true" -a -e ${JETTY_WEBAPP_DIR}/ext-2.2 ]; then
     # TODO
    echo "${JETTY_WEBAPP_DIR}/ext-2.2 already exists"
    cleanup_and_exit
  fi

  if [ "${addJars}" = "true" ]; then
    for jarPath in ${jarsPath//:/$'\n'}
    do
      found=`ls ${JETTY_LIB_DIR}/${jarPath} 2> /dev/null | wc -l`
      checkExec "looking for JAR ${jarPath} in ${JETTY_LIB_DIR}"
      if [ ! $found = 0 ]; then
        echo
        echo "${JETTY_LIB_DIR} already contains JAR ${jarPath}"
        cleanup_and_exit
      fi
      cp ${jarPath} ${JETTY_LIB_DIR}
      checkExec "copying jar ${jarPath} to '${JETTY_LIB_DIR}'"
    done
  fi
}

prepare_tomcat() {
  if [ "${prepareWar}" == "" ]; then
    echo "no arguments given"
    printUsage
    exit -1
  else
    if [ -e "${outputWar}" ]; then
        chmod -f u+w ${outputWar}
        rm -rf ${outputWar}
    fi
    rm -rf ${outputWarExpanded}

    check_adding_extensions

    prepare

    checkFileExists ${inputWar}
    checkFileDoesNotExist ${outputWar}

    check_extjs

    if [ "${addJars}" = "true" ]; then
        for jarPath in ${jarsPath//:/$'\n'}
        do
          checkFileExists ${jarPath}
        done
    fi

    #Unpacking original war
    unzip ${inputWar} -d ${tmpWarDir} > /dev/null
    checkExec "unzipping Oozie input WAR"

    components=""

    if [ "${OOZIE_USE_TOMCAT}" == "1" ]; then
      if [ "${secure}" != "" ]; then
        #Use the SSL version of server.xml in oozie-server
        checkFileExists ${secureConfigsDir}/ssl-server.xml
        cp ${secureConfigsDir}/ssl-server.xml ${CATALINA_BASE}/conf/server.xml
        #Inject the SSL version of web.xml in oozie war
        checkFileExists ${secureConfigsDir}/ssl-web.xml
        cp ${secureConfigsDir}/ssl-web.xml ${tmpWarDir}/WEB-INF/web.xml
        echo "INFO: Using secure server.xml and secure web.xml"
      else
        #Use the regular version of server.xml in oozie-server
        checkFileExists ${secureConfigsDir}/server.xml
        cp ${secureConfigsDir}/server.xml ${CATALINA_BASE}/conf/server.xml
        #No need to restore web.xml because its already in the original WAR file
      fi
    fi

    if [ "${addExtjs}" = "true" ]; then
      if [ ! "${components}" = "" ];then
        components="${components}, "
      fi
      components="${components}ExtJS library"
      if [ -e ${tmpWarDir}/ext-2.2 ]; then
        echo
        echo "Specified Oozie WAR '${inputWar}' already contains ExtJS library files"
        cleanup_and_exit
      fi
      #If the extjs path given is a ZIP, expand it and use it from there
      if [ -f ${extjsHome} ]; then
        unzip ${extjsHome} -d ${tmpDir} > /dev/null
        extjsHome=${tmpDir}/ext-2.2
      fi
      #Inject the library in oozie war
      cp -r ${extjsHome} ${tmpWarDir}/ext-2.2
      checkExec "copying ExtJS files into staging"
    fi

    if [ "${addJars}" = "true" ]; then
      if [ ! "${components}" = "" ];then
        components="${components}, "
      fi
      components="${components}JARs"

      for jarPath in ${jarsPath//:/$'\n'}
      do
        found=`ls ${tmpWarDir}/WEB-INF/lib/${jarPath} 2> /dev/null | wc -l`
        checkExec "looking for JAR ${jarPath} in input WAR"
        if [ ! $found = 0 ]; then
          echo
          echo "Specified Oozie WAR '${inputWar}' already contains JAR ${jarPath}"
          cleanup_and_exit
        fi
        cp ${jarPath} ${tmpWarDir}/WEB-INF/lib/
        checkExec "copying jar ${jarPath} to staging"
      done
    fi

    #Creating new Oozie WAR
    currentDir=`pwd`
    cd ${tmpWarDir}
    zip -r oozie.war * > /dev/null
    checkExec "creating new Oozie WAR"
    cd ${currentDir}

    #copying new Oozie WAR to asked location
    if [ "${OOZIE_USE_TOMCAT}" == "1" ]; then
      cp ${tmpWarDir}/oozie.war ${outputWar}
      checkExec "copying new Oozie WAR"

      echo
      echo "New Oozie WAR file with added '${components}' at ${outputWar}"
      echo
    fi

    cleanUp

    if [ "$?" -ne "0" ]; then
      exit -1
    fi

    log_ready_to_start

  fi
}

if [ "${OOZIE_USE_TOMCAT}" = "1" ]; then
  prepare_tomcat
else
  prepare_jetty
fi

log_ready_to_start
exit 0
