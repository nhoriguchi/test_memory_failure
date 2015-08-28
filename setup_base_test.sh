check_and_define_tp memeater
check_and_define_tp thugetlb
check_and_define_tp test_soft_offline_unpoison_stress

NUMNODE=$(numactl -H | grep available | cut -f2 -d' ')

reonline_memblocks() {
    local block=""
    local memblocks="$(find /sys/devices/system/memory/ -type d -maxdepth 1 | grep "memory/memory" | sed 's/.*memory//')"
    for mb in $memblocks ; do
        if [ "$(cat /sys/devices/system/memory/memory${mb}/state)" == "offline" ] ; then
            block="$block $mb"
        fi
    done
    echo "offlined memory blocks: $block"
    for mb in $block ; do
        echo "Re-online memory block $mb"
        echo online > /sys/devices/system/memory/memory${mb}/state
    done
}

prepare_base_memory_hotremove_pageblock_with_hwpoison() {
    prepare_system_default
}

cleanup_base_memory_hotremove_pageblock_with_hwpoison() {
	reonline_memblocks
    cleanup_system_default
}

control_base_memory_hotremove_pageblock_with_hwpoison() {
	bash $TRDIR/find_perferred_pageblock_for_hotremove.sh | tee $WDIR/preferred_pageblock
	local preferred_memblk=$(grep "^preferred memblk:" $WDIR/preferred_pageblock | awk '{print $3}')
	local preferred_memblk_pfn=$(grep "^preferred memblk start pfn:" $WDIR/preferred_pageblock | awk '{print $5}')

	$MCEINJECT -e hard-offline -a $preferred_memblk_pfn
	$PAGETYPES -b hwpoison

	echo offline > /sys/devices/system/memory/memory${preferred_memblk}/state
	if [ $? -eq 0 ] ; then
		echo "hot remove memblk $preferred_memblk succeeded."
		set_return_code HOTREMOVE_SUCCESS
	else
		echo "hot remove memblk $preferred_memblk failed."
		set_return_code HOTREMOVE_FAILURE
	fi

	set_return_code EXIT
}

check_base_memory_hotremove_pageblock_with_hwpoison() {
    check_system_default
}
