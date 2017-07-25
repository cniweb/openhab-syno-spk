#!/bin/sh

#--------openHAB2 installer script
#--------package based on work from pcloadletter.co.uk

DOWNLOAD_PATH="https://openhab.ci.cloudbees.com/job/openHAB-Distribution/lastSuccessfulBuild/artifact/distributions/openhab/target"
DOWNLOAD_FILE1="openhab-2.2.0-SNAPSHOT.tar.gz"

# Add more files by separating them using spaces
INSTALL_FILES="${DOWNLOAD_PATH}/${DOWNLOAD_FILE1}"

EXTRACTED_FOLDER="openHAB-2.2.0-SNAPSHOT"

DAEMON_USER="$(echo ${SYNOPKG_PKGNAME} | awk {'print tolower($_)'})"
DAEMON_PASS="$(openssl rand 12 -base64 2>nul)"
DAEMON_ID="${SYNOPKG_PKGNAME} daemon user"
DAEMON_ACL="user:${DAEMON_USER}:allow:rwxpdDaARWc--:fd--"
ENGINE_SCRIPT="start.sh"
PIDFILE="/var/services/homes/${DAEMON_USER}/.daemon.pid"

source /etc/profile

TEMP_FOLDER="$(find / -maxdepth 2 -name '@tmp' | head -n 1)"
PRIMARY_VOLUME="$(echo ${TEMP_FOLDER} | grep -oP '^/[^/]+')"
PUBLIC_FOLDER="$(synoshare --get public | grep -oP 'Path.+\[\K[^]]+')"

PUBLIC_OH_FOLDERS_EXISTS=no
PUBLIC_CONF="${PUBLIC_FOLDER}/openHAB2/conf"
PUBLIC_ADDONS="${PUBLIC_FOLDER}/openHAB2/addons"
TIMESTAMP="$(date +%Y%m)"
BACKUP_FOLDER="${SYNOPKG_PKGDEST}-backup-$TIMESTAMP"

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

  synoshare --get public > /dev/null || (
    echo "A shared folder called 'public' could not be found - note this name is case-sensitive. "
    echo "Please create this using the Shared Folder DSM Control Panel and try again."
    exit 1
  )

  echo "Get new version"
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
          if [ -z "${PUBLIC_FOLDER}" ]; then
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
  echo "Create '${DAEMON_USER}' daemon user"
  synouser --add ${DAEMON_USER} ${DAEMON_PASS} "${DAEMON_ID}" 0 "" ""
  sleep 3

  #add openhab user & handle possible device groups
  synogroup --member dialout ${DAEMON_USER}
  synogroup --member uucp ${DAEMON_USER}

  #determine the daemon user homedir and save that variable in the user's profile
  #this is needed because new users seem to inherit a HOME value of /root which they have no permissions for
  DAEMON_HOME="$(synouser --get ${DAEMON_USER} | grep -oP 'User Dir.+\[\K[^]]+')"
  su - ${DAEMON_USER} -s /bin/sh -c "echo export HOME=\'${DAEMON_HOME}\' >> .profile"
  su - ${DAEMON_USER} -s /bin/sh -c "echo export OPENHAB_PID=~/.daemon.pid >> .profile"

  #extract main archive
  echo "Install new version"
  cd ${TEMP_FOLDER}
  mkdir ${EXTRACTED_FOLDER}
  tar -xf ${TEMP_FOLDER}/${DOWNLOAD_FILE1} -C ${EXTRACTED_FOLDER} && rm ${TEMP_FOLDER}/${DOWNLOAD_FILE1}
  mv ${TEMP_FOLDER}/${EXTRACTED_FOLDER}/* ${SYNOPKG_PKGDEST}
  rmdir ${TEMP_FOLDER}/${EXTRACTED_FOLDER}
  chmod +x ${SYNOPKG_PKGDEST}/${ENGINE_SCRIPT}

  echo "Create conf/addon links"
  #if configdir exists in public folder -> create a symbolic link
  if [ -d ${PUBLIC_CONF} ]; then
    PUBLIC_OH_FOLDERS_EXISTS=yes
    mv -u ${SYNOPKG_PKGDEST}/conf/* ${PUBLIC_CONF}
    rm -r ${SYNOPKG_PKGDEST}/conf
    ln -s ${PUBLIC_CONF} ${SYNOPKG_PKGDEST}
    synoacltool -get ${PUBLIC_CONF} | grep -F ${DAEMON_ACL} > /dev/null || synoacltool -add ${PUBLIC_CONF} ${DAEMON_ACL}
  fi

  #if public addons dir exists in public folder -> create a symbolic link
  if [ -d ${PUBLIC_ADDONS} ]; then
    PUBLIC_OH_FOLDERS_EXISTS=yes
    mv -u ${SYNOPKG_PKGDEST}/addons/* ${PUBLIC_ADDONS}
    rm -r ${SYNOPKG_PKGDEST}/addons
    ln -s ${PUBLIC_ADDONS} ${SYNOPKG_PKGDEST}
    synoacltool -get ${PUBLIC_ADDONS} | grep -F ${DAEMON_ACL} > /dev/null || synoacltool -add ${PUBLIC_ADDONS} ${DAEMON_ACL}
  fi

  #add log file
  mkdir -p ${SYNOPKG_PKGDEST}/userdata/logs
  touch ${SYNOPKG_PKGDEST}/userdata/logs/openhab.log
  
  # Restore UserData if exists
  if [ -d ${BACKUP_FOLDER} ]; then
    cp -arf ${BACKUP_FOLDER}/userdata ${SYNOPKG_PKGDEST}/
  fi
  
  #change owner of folder tree
  echo "Fix permissions"
  if [ $PUBLIC_OH_FOLDERS_EXISTS == yes ]; then
    synoshare --setuser public RO + ${DAEMON_USER}
    chown -hR ${DAEMON_USER} ${PUBLIC_CONF}
    chown -hR ${DAEMON_USER} ${PUBLIC_ADDONS}
  fi
  chown -hR ${DAEMON_USER} ${SYNOPKG_PKGDEST}
  chmod -R u+w ${SYNOPKG_PKGDEST}/userdata

  #if Z-Wave dir exists -> change rights for binding
  if [ -d /dev/ttyACM0 ]; then
    chmod 777 /dev/ttyACM0
  fi
  if [ -d /dev/ttyACM1 ]; then
    chmod 777 /dev/ttyACM1
  fi
  
  echo "Installation done." > $SYNOPKG_TEMP_LOGFILE;

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
  #make sure server is stopped
  echo "Stop server"
  if su - ${DAEMON_USER} -s /bin/sh -c "cd ${SYNOPKG_PKGDEST}/runtime/karaf/bin && ./stop &"; then
    rm -f $PIDFILE
  fi
  sleep 10
  
  # Remove tmp, logs, cache and runtime dirs
  if [ -d ${SYNOPKG_PKGDEST}/userdata/tmp ]; then
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/tmp
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/cache ]; then
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/cache
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/log ]; then
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/log
  fi

  if [ -d ${SYNOPKG_PKGDEST}/userdata/logs ]; then
  	rm -rf ${SYNOPKG_PKGDEST}/userdata/logs
  fi
  
  if [ -d ${SYNOPKG_PKGDEST}/runtime ]; then
    rm -rf ${SYNOPKG_PKGDEST}/runtime
  fi
  
  # Remove openHAB system files...
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/all.policy
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/branding.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/branding-ssh.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/config.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/custom.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/version.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/distribution.info
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/jre.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/profile.cfg
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/startup.properties
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/org.apache.karaf*
  rm -f ${SYNOPKG_PKGDEST}/userdata/etc/org.ops4j.pax.url.mvn.cfg
  
  # Create backup
  mkdir -p ${BACKUP_FOLDER}/userdata
  mv ${SYNOPKG_PKGDEST}/userdata/* ${BACKUP_FOLDER}/userdata

  exit 0
}


postupgrade ()
{
  # Remove all backups after installation
  rm -rf ${SYNOPKG_PKGDEST}-backup*
  
  echo "Update done." > $SYNOPKG_TEMP_LOGFILE
  
  exit 0
}
