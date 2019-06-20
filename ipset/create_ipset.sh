#!/bin/sh
# create ipset from resolved ip's
# $1=no-update   - do not update ipset, only create if its absent

SCRIPT=$(readlink -f "$0")
EXEDIR=$(dirname "$SCRIPT")
IPSET_OPT="hashsize 262144 maxelem 1048576"
IP2NET="$EXEDIR/../ip2net/ip2net"

. "$EXEDIR/def.sh"
IPSET_CMD="$TMPDIR/ipset_cmd.txt"
IPSET_SAVERAM_CHUNK_SIZE=20000
IPSET_SAVERAM_MIN_FILESIZE=131072

[ "$1" = "no-update" ] && NO_UPDATE=1

file_extract_lines()
{
 # $1 - filename
 # $2 - from line (starting with 0)
 # $3 - line count
 # awk "{ err=1 } NR < $(($2+1)) { next } { print; err=0 } NR == $(($2+$3)) { exit err } END {exit err}" "$1"
 awk "NR < $(($2+1)) { next } { print } NR == $(($2+$3)) { exit }" "$1"
}
ipset_restore_chunked()
{
 # $1 - filename
 # $2 - chunk size
 local pos lines
 [ -f "$1" ] || return
 lines=$(wc -l <"$1")
 pos=$lines
 while [ "$pos" -gt "0" ]; do
    pos=$((pos-$2))
    [ "$pos" -lt "0" ] && pos=0
    file_extract_lines "$1" $pos $2 | ipset -! restore
    sed -i "$(($pos+1)),$ d" "$1"
 done
}


ipset_get_script()
{
 # $1 - filename
 # $2 - ipset name
 # $3 - exclude file
 # $4 - "6" = ipv6
 local filter="sort -u"
 [ -x "$IP2NET" ] && [ "$4" != "6" ] && filter="$IP2NET"  
 if [ -f "$3" ] ; then
  zzcat "$1" | grep -vxFf "$3" | $filter | sed -nre "s/^.+$/add $2 &/p"
 else
  zzcat "$1" | $filter | sed -nre "s/^.+$/add $2 &/p"
 fi
}

ipset_restore()
{
 # $1 - filename
 # $2 - ipset name
 # $3 - exclude file
 # $4 - "6" = ipv6
 zzexist "$1" || return
 local fsize=$(zzsize "$1")
 local svram=0
 # do not saveram small files. file can also be gzipped
 [ "$SAVERAM" = "1" ] && [ "$fsize" -ge "$IPSET_SAVERAM_MIN_FILESIZE" ] && svram=1

 local T="Adding to ipset $2 ($IPSTYPE"
 [ -x "$IP2NET" ] && [ "$4" != "6" ] && T="$T, ip2net"
 [ "$svram" = "1" ] && T="$T, saveram"
 T="$T) : $f"
 echo $T

 if [ "$svram" = "1" ]; then
  ipset_get_script "$1" "$2" "$3" "$4" >"$IPSET_CMD"
  ipset_restore_chunked "$IPSET_CMD" $IPSET_SAVERAM_CHUNK_SIZE
  rm -f "$IPSET_CMD"
 else
  ipset_get_script "$1" "$2" "$3" "$4" | ipset -! restore
 fi
}

create_ipset()
{
local IPSTYPE
if [ -x "$IP2NET" ]; then
 IPSTYPE=hash:net
else
 IPSTYPE=$1
fi
ipset create $2 $IPSTYPE $IPSET_OPT 2>/dev/null || {
 [ "$NO_UPDATE" = "1" ] && return
}
ipset flush $2
for f in "$3" "$4" ; do
 ipset_restore "$f" "$2" "$5" 4
done
return 0
}

create_ipset6()
{
local IPSTYPE=$1
ipset create $2 $IPSTYPE $IPSET_OPT family inet6 2>/dev/null || {
 [ "$NO_UPDATE" = "1" ] && return
}
ipset flush $2
for f in "$3" "$4"; do
 ipset_restore "$f" "$2" "$5" 6
done
return 0
}

# ipset seem to buffer the whole script to memory
# on low RAM system this can cause oom errors
# in SAVERAM mode we feed script lines in portions starting from the end, while truncating source file to free /tmp space
RAMSIZE=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SAVERAM=0
[ "$RAMSIZE" -lt "110000" ] && SAVERAM=1

[ "$DISABLE_IPV4" != "1" ] && {
  create_ipset hash:ip $ZIPSET "$ZIPLIST" "$ZIPLIST_USER" "$ZIPLIST_EXCLUDE"
  create_ipset hash:ip $ZIPSET_IPBAN "$ZIPLIST_IPBAN" "$ZIPLIST_USER_IPBAN" "$ZIPLIST_EXCLUDE"
}

[ "$DISABLE_IPV6" != "1" ] && {
  create_ipset6 hash:ip $ZIPSET6 "$ZIPLIST6" "$ZIPLIST_USER6" "$ZIPLIST_EXCLUDE6"
  create_ipset6 hash:ip $ZIPSET_IPBAN6 "$ZIPLIST_IPBAN6" "$ZIPLIST_USER_IPBAN6" "$ZIPLIST_EXCLUDE6"
}

true
