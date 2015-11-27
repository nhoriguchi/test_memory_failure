#!/bin/bash

MEMBLKSIZE=0x8000 # in page
PAGETYPES=/src/linux-dev/tools/vm/page-types

if [ ! -x "$PAGETYPES" ] ; then
	echo "$PAGETYPES not found" >&2
	exit 1
fi

TMPD=$(mktemp -d)
EST_MAXPFN=0
# Rough estimate of max_pfn
paste <(grep start_pfn /proc/zoneinfo | awk '{print $2}') <(grep spanned /proc/zoneinfo | awk '{print $2}') > $TMPD/zoneinfo
while read start span ; do
	if [ "$EST_MAXPFN" -lt "$[start + span]" ] ; then
		EST_MAXPFN=$[start + span]
	fi
done < $TMPD/zoneinfo

echo "estimated max pfn: $EST_MAXPFN"
EST_MAXMEMBLK=$[EST_MAXPFN / 0x8000 + 1]
echo "estimated max memblk: $EST_MAXMEMBLK"

for i in $(seq $EST_MAXMEMBLK) ; do
	$PAGETYPES -a $[i * MEMBLKSIZE]+$MEMBLKSIZE | grep ^0x > $TMPD/pagetypes
	nopage=$(grep ^0x0000000000100000 $TMPD/pagetypes | awk '{print $2}')
	noflag=$(grep ^0x0000000000000000 $TMPD/pagetypes | awk '{print $2}')
	buddy=$(grep ^0x0000000000000400 $TMPD/pagetypes | awk '{print $2}')

	if [ "$noflag" == 32736 ] && [ "$buddy" == 32 ] ; then
		printf "preferred memblk: %d\n" $i
		printf "preferred memblk start pfn: 0x%lx\n" $[i * MEMBLKSIZE]
		exit 0
	fi
done

echo "preferred memblk: --- (not found)"
exit 1
