#!/bin/bash

THISDIR=$(dirname $(readlink -f $BASH_SOURCE))
TESTCORE=${THISDIR}/test_core/run-test.sh

RECIPE=""
TESTNAME="sample"
VERBOSE=""
SCRIPT=""
while getopts "r:n:vS" OPT ; do
    case $OPT in
        r) RECIPE="${OPTARG}" ;;
        n) TESTNAME="${OPTARG}" ;;
        v) VERBOSE="-v" ;;
        S) SCRIPT="-S"
    esac
done
shift $[OPTIND-1]

[ ! -f ${TESTCORE} ] && echo "No test_core on ${THISDIR}/test_core." && exit 1

TESTCASE_FILTER="$@"
[ "$TESTCASE_FILTER" ] && TESTCASE_FILTER="-f \"${TESTCASE_FILTER}\""

[ ! "${RECIPE}" ] && echo "recipe not specified. use -r option."
echo "bash ${TESTCORE} ${VERBOSE} -t ${TESTNAME} ${TESTCASE_FILTER} ${SCRIPT} ${RECIPE}"
eval bash ${TESTCORE} ${VERBOSE} -t ${TESTNAME} ${TESTCASE_FILTER} ${SCRIPT} ${RECIPE}
