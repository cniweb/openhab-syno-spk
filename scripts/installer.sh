#!/bin/sh

#--------OpenHAB installer script
#--------package based on work from pcloadletter.co.uk

DOWNLOAD_PATH="https://openhab.ci.cloudbees.com/job/openHAB-Distribution/lastSuccessfulBuild/artifact/distributions/openhab/target"
DOWNLOAD_FILE1="openhab-2.0.0-SNAPSHOT.zip"

# Add more files by separating them using spaces
INSTALL_FILES="${DOWNLOAD_PATH}/${DOWNLOAD_FILE1}"

EXTRACTED_FOLDER="OpenHAB-runtime-2.0.0-SNAPSHOT"

DAEMON_USER="$(echo ${SYNOPKG_PKGNAME} | awk {'print tolower($_)'})"
DAEMON_PASS="$(openssl rand 12 -base64 2>nul)"
DAEMON_ID="${SYNOPKG_PKGNAME} daemon user"
ENGINE_SCRIPT="start.sh"

source /etc/profile

TEMP_FOLDER="$(find / -maxdepth 2 -name '@tmp' | head -n 1)"
PRIMARY_VOLUME="$(echo ${TEMP_FOLDER} | grep -oP '^/[^/]+')"
PUBLIC_FOLDER="$(synoshare --get public | grep -oP 'Path.+\[\K[^]]+')"
PUBLIC_CONF="${PUBLIC_FOLDER}/openHAB/configurations"
PUBLIC_ADDONS="${PUBLIC_FOLDER}/openHAB/addons"

preinst ()
{
  # Is Java properly installed?
  if [[ -z "${JAVA_HOME}" || ! -f "${JAVA_HOME}/bin/java" ]]; then
    echo "Java is not installed or not properly configured."
    echo "Download and install as described on http://wp.me/pVshC-z5"
    echo "The Synology provided Java may not work with OpenHAB."
    exit 1
  fi

  # Is the User Home service enabled?
  UH_SERVICE=$(synogetkeyvalue /etc/synoinfo.conf userHomeEnable)
  if [ "${UH_SERVICE}" == "no" ]; then
    echo "The User Home service is not enabled. Please enable this feature in the User control panel in DSM."
    exit 1
  fi

  cd ${TEMP_FOLDER}
  # go through list of files
  for WGET_URL in ${INSTALL_FILES}; do
    WGET_FILENAME="$(echo ${WGET_URL} | sed -r "s%^.*/(.*)%\1%")"
    echo "Processing ${WGET_FILENAME}"
    [ -f "${TEMP_FOLDER}/${WGET_FILENAME}" ] && rm ${TEMP_FOLDER}/${WGET_FILENAME}
    # use local file first
    if [ -f "${PUBLIC_FOLDER}/${WGET_FILENAME}" ]; then
      echo "Found file locally - copying"
      cp ${PUBLIC_FOLDER}/${WGET_FILENAME} ${TEMP_FOLDER}
    else
      wget -nv --no-check-certificate --output-document=${WGET_FILENAME} ${WGET_URL}
      if [[ $? != 0 ]]; then
          echo "There was a problem downloading ${WGET_FILENAME} from the download link:"
          echo "'${WGET_URL}'"
          echo "Alternatively, download this file manually and place it in the 'public' shared folder and start installation again."
          if [ -z "${PUBLIC_FOLDER}" ];then
            echo "Note: You must create a 'public' shared folder first on your primary volume"
          fi
          exit 1
      fi
    fi
  done

  exit 0
}


postinst ()
{
  #create daemon user
  synouser --add ${DAEMON_USER} ${DAEMON_PASS} "${DAEMON_ID}" 0 "" ""
  sleep 3

  #determine the daemon user homedir and save that variable in the user's profile
  #this is needed because new users seem to inherit a HOME value of /root which they have no permissions for
  DAEMON_HOME="$(synouser --get ${DAEMON_USER} | grep -oP 'User Dir.+\[\K[^]]+')"
  su - ${DAEMON_USER} -s /bin/sh -c "echo export HOME=\'${DAEMON_HOME}\' >> .profile"
  su - ${DAEMON_USER} -s /bin/sh -c "echo export OPENHAB_PID=~/.daemon.pid >> .profile"

  #extract main archive
  cd ${TEMP_FOLDER}
  7z x ${TEMP_FOLDER}/${DOWNLOAD_FILE1} -o${EXTRACTED_FOLDER} && rm ${TEMP_FOLDER}/${DOWNLOAD_FILE1}
  mv ${TEMP_FOLDER}/${EXTRACTED_FOLDER}/* ${SYNOPKG_PKGDEST}
  rmdir ${TEMP_FOLDER}/${EXTRACTED_FOLDER}
  chmod +x ${SYNOPKG_PKGDEST}/${ENGINE_SCRIPT}

  #change owner of folder tree
  chown -R ${DAEMON_USER} ${SYNOPKG_PKGDEST}

  #if Z-Wave dir exists -> change rights for binding
  if [ -d /dev/ttyACM0 ]; then
    chmod 777 /dev/ttyACM0
  fi
  if [ -d /dev/ttyACM1 ]; then
    chmod 777 /dev/ttyACM1
  fi

  exit 0
}


preuninst ()
{
  #make sure server is stopped
  if su - ${DAEMON_USER} -s /bin/sh -c "cd ${SYNOPKG_PKGDEST}/runtime/karaf/bin && ./stop &"; then
    rm -f $PIDFILE
  fi
  sleep 10

  exit 0
}


postuninst ()
{
  # Determine folder before deleting daemon
  DAEMON_HOME="$(synouser --get ${DAEMON_USER} | grep -oP 'User Dir.+\[\K[^]]+')"

  # Remove daemon user
  synouser --del ${DAEMON_USER}
  sleep 3

  # Sanity check daemon had valid folder
  if [ -e "${DAEMON_HOME}" ]; then
    rm -r "${DAEMON_HOME}"
  else
    echo "Daemon user folder '${DAEMON_HOME}' not found - nothing deleted"
  fi

  exit 0
}


preupgrade ()
{
  # Remove tmp, logs & cache dirs
  if [ -d ${SYNOPKG_PKGDEST}/userdata/tmp ]; then
  	echo "Remove tmp"
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/tmp
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/cache ]; then
  	echo "Remove cache"
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/cache
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/log ]; then
  	echo "Remove log"
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/log
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/logs ]; then
  	echo "Remove logs"
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/logs
  fi

  # backup current installation with settings
  echo "Backup"
  TIMESTAMP=`date +%Y%m%d_%H%M%S`;
  sudo mv ${SYNOPKG_PKGDEST} /${SYNOPKG_PKGDEST}-backup-$TIMESTAMP

  exit 0
}


postupgrade ()
{
# restore configuration and userdata
echo "Restore UserData"
sudo cp -arv ${SYNOPKG_PKGDEST}-backup-$TIMESTAMP/userdata ${SYNOPKG_PKGDEST}/

echo "create conf/addon links"
  #if configdir exists in public folder -> create a symbolic link
  if [ -d ${PUBLIC_CONF} ]; then
    rm -r ${SYNOPKG_PKGDEST}/conf
    ln -s ${PUBLIC_CONF} ${SYNOPKG_PKGDEST}
  fi

  #if public addons dir exists in public folder -> create a symbolic link
  if [ -d ${PUBLIC_ADDONS} ]; then
    rm -r ${SYNOPKG_PKGDEST}/addons
    ln -s ${PUBLIC_ADDONS} ${SYNOPKG_PKGDEST}
  fi

# fix permissions
echo "fix permssion"
sudo chown -hR openhab2:users ${SYNOPKG_PKGDEST}

exit 0
}
