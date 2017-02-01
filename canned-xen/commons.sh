#!/bin/bashB

SETCOLOR_STATUS_OK="echo -en \\033[1;32m"
SETCOLOR_STATUS_UNKNOWN="echo -en \\033[1;33m"
SETCOLOR_STATUS_FAIL="echo -en \\033[1;31m"
SETCOLOR_HEAD="echo -en \\033[1;37m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"




# echo_announce
# echo_announce_n
# echo_ok
# echo_fail
# echo_unknown


echo_announce() {
    echo_announce_n "$1"
    echo  "   ===="
    return 0
}

echo_announce_n() {
    PARENT_COMMAND="$(ps -o comm= $PPID)"
    echo -ne '\033]0;'${0}' | ' "${1}" '\007'
    echo -n "====   "
    $SETCOLOR_HEAD
    echo -n "$1"
    $SETCOLOR_NORMAL
    return 0
}

echo_ok() {
    echo -n "  [ "
    $SETCOLOR_STATUS_OK
    echo -n "OK"
    $SETCOLOR_NORMAL
    echo  " ]"
    return 0
}

echo_fail() {
    echo -n "  [ "
    $SETCOLOR_STATUS_FAIL
    echo -n "ERR"
    $SETCOLOR_NORMAL
    echo  " ]"
    return 0
}

echo_unknown() {
    echo -n "  [ "
    $SETCOLOR_STATUS_UNKNOWN
    echo -n "???"
    $SETCOLOR_NORMAL
    echo  " ]"
    return 0
}


pw_request_hint() {
    if ! sudo -n true 2>/dev/null; then 
	$SETCOLOR_STATUS_FAIL
	echo -n "Password required:"
	$SETCOLOR_NORMAL
	echo 
    fi

    return 0
}

my_sudo() {
    pw_request_hint
    sudo $@
}


getLatestFileFromUrl() {
    URL=$1
    SEARCH=$2
    GREPSEARCH=$3
    FILENAME="`wget -qO- "${URL}?C=M;O=A;F=0;P=${SEARCH}" | grep "href"| grep "${GREPSEARCH}" | grep -v "snapshot" | sed 's/.*href=\"\(.*\)\".*/\1/' | sort -t - -V -k 2,2 | awk '/./{line=$0} END{print line}'`"
    echo "$FILENAME"
}

download() {
    NAME=$1
    URL=$2
    FILE=$3
    DESTDIR=$4
    SEARCH=$5
    UNTARCMD=$6
    UNTARFILE=$7
    
    echo_announce "downloading ${NAME} from \"${URL}${FILE}\"... "
    if [ -e "downloads/${FILE##*/}" ]; then
	echo "skipping download, file \"${FILE##*/}\" exists already in \"${DESTDIR}\" folder."
	echo_unknown
    else
	wget -P downloads/ "${URL}${FILE}"
	echo_ok
    fi
    if ! ls ${SEARCH} 1> /dev/null 2>&1; then
	echo_announce "${NAME} untar"
	tar ${UNTARCMD} downloads/${UNTARFILE}
	echo_ok
    else
	echo "${NAME} has been already untared"
	echo_unknown
    fi
}


create_dir() {
    DIRNAME=$1
    DESCRIPTION=$2
    echo_announce_n "creating ${DESCRIPTION} directory \"${DIRNAME}\"... "
    if [ ! -d ${DIRNAME} ]; then
	mkdir ${DIRNAME}
	echo_ok
    else
	echo -n "OK - was existing already."
	echo_unknown
    fi

}


