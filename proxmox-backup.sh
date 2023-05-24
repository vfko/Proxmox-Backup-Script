#!/bin/bash

############################
#     Global Variables     #
############################
VMID=$1
MAX_BACKUPS=$2
STORAGE=$3
COMPRESS=$4
MAIL_TO=$5
TEMP_FILE=$HOME/temp.file
TEMP_FILE_1=$HOME/temp.file_1

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
  echo -e "    #############################"
  echo -e "    # HOW TO USE PROXMOX-BACKUP #"
  echo -e "    ############################# \n\n"
  echo -e "    Make backup:"
  echo -e "                     proxmox-backup.sh <vmid> <max_backups> <storage> <compress_format> <email> \n\n"
  echo -e "    <vmid>: ID of virtual machine or container \n"
  echo -e "    <max_backups>: number of backups kept, older backups will be deleted \n"
  echo -e "    <storage>: name of storage \n"
  echo -e "    <compress_format>: type of compression lzo/gzip/zstd - optional (default=lzo) \n"
  echo -e "    <email>: email for notification - optional \n\n"
  echo -e "    Example: proxmox-backup.sh 101 5 My-backup-storage zstd my.email@my-domain.com\n"
}

checkIfStorageExist () {
  LINE_WITH_STORAGE=(`cat -n /etc/pve/storage.cfg | grep "$1"`)
  if [ -z $LINE_WITH_STORAGE ]; then
    echo "Storage doesn't exist"
    exit
  fi
}

checkIfVmidExist () {
  VMID_CONFIG=(`/usr/sbin/qm config $1 2> /dev/null`)
  CONTAINER_CONFIG=(`/usr/sbin/pct config $1 2> /dev/null`)

  if [[ -z $VMID_CONFIG && -z $CONTAINER_CONFIG ]]; then
    echo "VMID or CTID doesn't exist"
    exit
  fi
}

getStoragePath () {
  cat -n /etc/pve/storage.cfg | grep ": $1" > $TEMP_FILE
  CONFIG_LINE_WITH_STORAGE=(`cat $TEMP_FILE`)
  NUM_OF_LINE=${CONFIG_LINE_WITH_STORAGE[0]}
  NUM_OF_LINE_WITH_PATH=$((NUM_OF_LINE + 1))
  cat -n /etc/pve/storage.cfg | grep $NUM_OF_LINE_WITH_PATH > $TEMP_FILE
  cat $TEMP_FILE | grep "path" > $TEMP_FILE_1
  LINE_WITH_PATH=(`cat $TEMP_FILE_1`)

  for i in ${!LINE_WITH_PATH[@]}; do
    if [ ${LINE_WITH_PATH[$i]} == "path" ]; then
      index=$((i + 1))
      STORAGE_PATH=${LINE_WITH_PATH[$index]}
    fi
  done

  RESULT="$STORAGE_PATH/dump"

  if [ ${RESULT:0:5} == "/dump" ]; then
    echo "Can't get path to storage."
    exit
  else
    echo $RESULT
  fi
}

isRootUser () {
  if [ "`id -u`" != 0 ]; then
    echo "Access denied!"
    exit
  fi
}

checkIfCompressFormatIsValid() {
  ENTRY_FORMAT=$1
  USAGE_COMPRESS_FORMAT=( "zstd" "ZSTD" "lzo" "LZO" "gzip" "GZIP" )
  IS_IN_ARRAY=0
  for i in ${USAGE_COMPRESS_FORMAT[@]}; do
    if [ "$i" == "$ENTRY_FORMAT" ]; then
      IS_IN_ARRAY=1
    fi
  done
  if [ $IS_IN_ARRAY -eq 0 ]; then
    echo -e "\nCompress format is not valid."
    echo -e "Compress formats: zstd/lzo/gzip \n"
    echo -e "Try \`proxmox-backup.sh help\` \n"
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

# validate compress format
checkIfCompressFormatIsValid $COMPERSS
COMPERSS=(`echo ${COMPERSS,,}`)

# create temp files
touch $TEMP_FILE
touch $TEMP_FILE_1

# load all backups
STORAGE_PATH=`getStoragePath $STORAGE`
ls -rt $STORAGE_PATH | grep "qemu-$VMID" > $TEMP_FILE 
ls -rt $STORAGE_PATH | grep "lxc-$VMID" >> $TEMP_FILE
FILES=(`cat $TEMP_FILE`)
BACKUP_FILES=()

for i in ${FILES[@]}; do
  if [[ ${i:(-4)} == ".lzo" || ${i:(-3)} == ".gz" || ${i:(-4)} == ".zst" ]]; then
    if [[ ${i:12:${#VMID}} == $VMID || ${i:11:${#VMID}} == $VMID ]]; then
      BACKUP_FILES+=($i)
    fi
  fi
done

# remove old backups
NUM_OF_BACKUPS=${#BACKUP_FILES[@]}
INDEX=0

while [ $((NUM_OF_BACKUPS)) -ge $((MAX_BACKUPS)) ]; do

  # remove old .lzo files
  if [ "${BACKUP_FILES[$INDEX]:(-4)}" == ".lzo" ]; then
    
    if [ "${BACKUP_FILES[$INDEX]:(-8)}" == ".vma.lzo" ]; then
      FILE_NAME=${BACKUP_FILES[$INDEX]//".vma.lzo"/""}
    else
      FILE_NAME=${BACKUP_FILES[$INDEX]//".tar.lzo"/""}
    fi

    LOG="$STORAGE_PATH/$FILE_NAME.log"
    LXC_NOTES="$STORAGE_PATH/$FILE_NAME.tar.lzo.notes"

    rm "$STORAGE_PATH/${BACKUP_FILES[$INDEX]}"

    if [[ -f $LOG ]]; then
      rm "$LOG"
    fi
    if [[ -f $LXC_NOTES ]]; then
      rm "$LXC_NOTES"
    fi

  # remove old .gz files
  elif [ "${BACKUP_FILES[$INDEX]:(-3)}" == ".gz" ]; then
    
    if [ "${BACKUP_FILES[$INDEX]:(-7)}" == ".vma.gz" ]; then
      FILE_NAME=${BACKUP_FILES[$INDEX]//".vma.gz"/""}
    else
      FILE_NAME=${BACKUP_FILES[$INDEX]//".tar.gz"/""}
    fi

    LXC_NOTES="$STORAGE_PATH/$FILE_NAME.tar.gz.notes"
    LOG="$STORAGE_PATH/$FILE_NAME.log"

    rm "$STORAGE_PATH/${BACKUP_FILES[$INDEX]}"

    if [[ -f $LOG ]]; then
      rm "$LOG"
    fi
    if [[ -f $LXC_NOTES ]]; then
      rm "$LXC_NOTES"
    fi

  # remove old .zst files
  elif [ "${BACKUP_FILES[$INDEX]:(-4)}" == ".zst" ]; then
    
    if [ "${BACKUP_FILES[$INDEX]:(-8)}" == ".vma.zst" ]; then
      FILE_NAME=${BACKUP_FILES[$INDEX]//".vma.zst"/""}
    else
      FILE_NAME=${BACKUP_FILES[$INDEX]//".tar.zst"/""}
    fi
    LOG="$STORAGE_PATH/$FILE_NAME.log"
    LXC_NOTES="$STORAGE_PATH/$FILE_NAME.tar.zst.notes"

    rm "$STORAGE_PATH/${BACKUP_FILES[$INDEX]}"

    if [[ -f $LOG ]]; then
      rm "$LOG"
    fi
    if [[ -f $LXC_NOTES ]]; then
      rm "$LXC_NOTES"
    fi

  fi
  INDEX=$((INDEX + 1))
  NUM_OF_BACKUPS=$((NUM_OF_BACKUPS - 1))
done

# remove temp files
rm $TEMP_FILE
rm $TEMP_FILE_1

# make backup
/usr/bin/vzdump $((VMID)) --compress $COMPRESS  --storage $STORAGE --mailto $MAIL_TO
