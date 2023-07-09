#!/bin/bash

export PATH=/sbin:/bin:/usr/bin:/usr/local/bin

if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

cgreen='\033[0;32m'
ccyan='\033[0;36m'
cyellow='\033[0;33m'
cclear='\033[0m'

SCRIPT_NAME="$(basename -- $0)"
SCRIPT_VERSION="1.0"
USAGE="usage: $SCRIPT_NAME [-c][-q][-p] <source directory> <destination directory> [-v][-h]"

while getopts cqpvh flag
do
    case "${flag}" in
        c) COMPRESS="true";;
        q) QUIET_MODE="true";;
        p) KEEP_PERMS="true";;
        v) echo $SCRIPT_NAME "v"$SCRIPT_VERSION 1>&2; exit 1;;
        h|\?) echo $USAGE 1>&2; exit 1;;
    esac
done

shift $((OPTIND-1))

SRCDIR=${1:-"/var/log"}
OUTDIR=${2:-"/var/backups/logs"}
LOGDIR="${OUTDIR}/files"
HSHDIR="${OUTDIR}/hashes"

if [ $# -eq 0 ]; then
    read -p "No arguments provided, defaulting to backup from ${SRCDIR} to ${LOGDIR}. Proceed (Y/n)? " -r REPLY
    echo -n
    
    if echo $REPLY | grep -Eq '^([Yy]|)$'; then
        echo "Proceeding..."
    else
        echo "Please specify source and destination paths"
        echo $USAGE 1>&2
        exit 1
    fi
fi

mkdir -p "$LOGDIR"
mkdir -p "$HSHDIR"

timestamp=$(date --utc "+%Y-%m-%dT%H%M%SZ")  # ISO 8601 compliant

ERRFIL="${OUTDIR}/error-${timestamp}.log"
exec 2>> "$ERRFIL"

hash_file="${HSHDIR}/hashed-${timestamp}.txt"
hash_file_header="Original files MD5 hashed on $(date -u)"

echo "$hash_file_header" >> "$hash_file"
for i in $(seq 1 $(echo $hash_file_header | wc -c));do echo -n '-' >> "$hash_file";done; echo >> "$hash_file"

file_list=$(find ${SRCDIR} -type f -name *.log* | sort)
file_count=$(echo "$file_list" | wc -l)

if [ "$QUIET_MODE" != "true" ]; then
    /bin/echo -e "\n[+] Backing up ${file_count} file(s) from ${SRCDIR} to ${LOGDIR} ...\n"
fi

t_start=`date +%s`
count=0
for file in $file_list
do
    dest_file=${LOGDIR}/"$(basename -- "$file" ".""${file#*.}")""-"${timestamp}".""${file#*.}"
    shared_header="$(basename -- "$file") to $(basename -- "$dest_file")"
    
    cpcmd=( cp )
    if [ "$KEEP_PERMS" = "true" ]; then
        cpcmd+=( -p )
    fi
    cpcmd+=( "$file" "$dest_file" )    

    if [ "$COMPRESS" != "true" ] || file "$file" | grep -q compressed; then
        if [ "$QUIET_MODE" != "true" ]; then
            echo "Copying $shared_header"
        fi
        "${cpcmd[@]}" && dest_hash=$(md5sum "$dest_file" | cut -d' ' -f1)
    else
        if [ "$QUIET_MODE" != "true" ]; then
            echo "Copying and compressing ${shared_header}.gz"
        fi
        "${cpcmd[@]}" && dest_hash=$(md5sum "$dest_file" | cut -d' ' -f1)
        gzip "${dest_file}"
    fi
    
    orig_hash=$(md5sum "$file" | cut -d' ' -f1)
    echo "$orig_hash   $file" >> "$hash_file"
    
    if [ "$orig_hash" = "$dest_hash" ]; then
        count=$[$count +1]
    else
        echo "Invalid checksum for $dest_file" 1>&2
    fi
done

t_end=`date +%s`

if [ "$QUIET_MODE" != "true" ]; then
    /bin/echo -e "\n[+] Completed in $((t_end-t_start)) second(s)"
    /bin/echo -e "[+] Backed up $count file(s) to $LOGDIR"
    /bin/echo -e "[+] Saved file checksums to $hash_file"
fi

if [ $count -lt $file_count ]; then
    errmsg="Failed to transfer $((file_count-count)) file(s)"
    if [ "$QUIET_MODE" != "true" ]; then
        /bin/echo -ne "\n[!] "
        echo "$errmsg" | tee -a "$ERRFIL"
    else
        echo "$errmsg" 1>&2
    fi
fi

if [ -s "$ERRFIL" ]; then
    if [ "$QUIET_MODE" != "true" ]; then
        /bin/echo -e "[!] 1 or more errors occurred, view details in $ERRFIL"
    fi
    exit 1
else
    rm -f "$ERRFIL"
fi