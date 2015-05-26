check_mce_capability() {
    local cap=$(staprun check_mce_capability.ko | cut -f2 -d' ')
    [ ! "$cap" ] && echo "Failed to retrieve MCE CAPABILITY info. SKIPPED." && return 1
    # check 1 << 24 (MCG_SER_P)
    if [ $[ $cap & 16777216 ] -eq 16777216 ] ; then
        return 0
    else
        echo "MCE_SER_P is cleared in the current system."
        return 1
    fi
}
