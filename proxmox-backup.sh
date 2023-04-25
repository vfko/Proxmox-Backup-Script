#!/bin/bash

############################
#     Global Variables     #
############################
VMID=$1
MAX_BACKUPS=$2
STORAGE=$3
COMPRESS=$4
MAIL_TO=$5

# set optional variables
if [[ -z $COMPERSS ]]; then
  COMPERSS="lzo"
fi

if [[ -z $MAIL_TO ]]; then
  MAIL_TO="nobody@nodomain.no"
fi

#####################
#     Functions     #
#####################

getHelp () {
  echo -e "\n"
  echo -e "    #################################"
  echo -e "    # JAK PRACOVAT S PROXMOX-BACKUP #"
  echo -e "    ################################# \n\n"
  echo -e "    Vyvolání zálohy:"
  echo -e "                     proxmox-backup <vmid> <max_backups> <storage> <komprese> <email> \n\n"
  echo -e "    <vmid>: ID vyrtuálního stroje - povinný údaj \n"
  echo -e "    <max_backups>: maximální počet uchovaných záloh - povinný údaj \n"
  echo -e "    <storage>: název storage - povinný údaj \n"
  echo -e "    <komprese>: druh komprese lzo/gz - nepovinný údaj (výchozí=lzo) \n"
  echo -e "    <email>: email pro notifikaci - nepovinný údaj \n"
}

checkIfStorageExist () {
  LINE_WITH_STORAGE=(`cat -n /etc/pve/storage.cfg | grep "$1"`)
  if [ -z $LINE_WITH_STORAGE ]; then
    echo "Storage neexistuje"
    exit
  fi
}

checkIfVmidExist () {
  VMID_CONFIG=(`/usr/sbin/qm config $1 2> /dev/null`)
  if [ -z $VMID_CONFIG ]; then
    echo "VMID neexistuje"
    exit
  fi
}

getStoragePath () {
  LINE_WITH_STORAGE=(`cat -n /etc/pve/storage.cfg | grep "$1"`)
  NUM_OF_STORAGE_LINE=${LINE_WITH_STORAGE[0]}
  NUM_OF_LINE_WITH_PATH=$((NUM_OF_STORAGE_LINE + 1))
  GREP_LINES=(`cat -n /etc/pve/storage.cfg | grep $NUM_OF_LINE_WITH_PATH`)

  for i in ${!GREP_LINES[@]}; do
    if [ ${GREP_LINES[$i]} == "path" ]; then
      index=$((i + 1))
      STORAGE_PATH=${GREP_LINES[$index]}
    fi
  done

  RESULT="$STORAGE_PATH/dump"

  if [ ${RESULT:0:5} == "/dump" ]; then
    echo "Nepodařilo se získat cesu k storage."
    exit
  else
    echo $RESULT
  fi
}

isRootUser () {
  USER_GROUPS=(`groups $USER`)
  IN_SUDO=0

  for group in ${USER_GROUPS[@]}; do
    if [ $group == "sudo" ]; then
      IN_SUDO=1
    fi
  done

  if [ "`id -u`" != 0 ] && [ $IN_SUDO -ne 1 ]; then
    echo "Přístup zamítnut!"
    exit
  fi
}

########################
#     Main routine     #
########################

if [[ $1 == "" || $1 == "help" ]]; then
  getHelp
  exit
fi

# authorization
isRootUser

# check VMID
checkIfVmidExist $VMID

# check storage
checkIfStorageExist $STORAGE

# load all backups
FILES=($(ls -rt `getStoragePath $STORAGE`))
BACKUP_FILES=()

for i in ${FILES[@]}; do
  if [[ ${i:(-4)} == ".lzo" || ${i:(-3)} == ".gz" ]]; then
    if [ ${i:12:${#VMID}} == $VMID ]; then
      BACKUP_FILES+=($i)
    fi
  fi
done

# remove old backups
STORAGE_PATH=`getStoragePath $STORAGE`
NUM_OF_BACKUPS=${#BACKUP_FILES[@]}
INDEX=0

while [ $((NUM_OF_BACKUPS)) -ge $((MAX_BACKUPS)) ]; do
  if [ "${BACKUP_FILES[0]:(-4)}" == ".lzo" ]; then
    rm "$STORAGE_PATH/${BACKUP_FILES[0]}"
    LOG=${BACKUP_FILES[0]//".vma.lzo"/""}
    LOG="$LOG.log"
    rm "$STORAGE_PATH/$LOG"
  elif [ "${BACKUP_FILES[0]:(-3)}" == ".gz" ]; then
    rm "$STORAGE_PATH/${BACKUP_FILES[0]}"
    LOG=${BACKUP_FILES[0]//".vma.gz"/""}
    LOG="$LOG.log"
    rm "$STORAGE_PATH/$LOG"
  fi
  unset BACKUP_FILES[$((INDEX))]
  INDEX=$((INDEX + 1))
  NUM_OF_BACKUPS=$((NUM_OF_BACKUPS - 1))
done


# make backup
/usr/bin/vzdump $((VMID)) --compress $COMPRESS  --storage $STORAGE --mailto $MAIL_TO