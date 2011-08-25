#!/bin/bash

# Useful debugging script:
#
# 1) Create a gdb init file that maps in the trigence libs so that you can
#    break in the controller.
# 2) Optionally set up a source search path so gdb will find source in
#    your repository.
# 3) Attach to the process.  At that point, you can set breakpoints in
#    the runtime.

usage()
{
	echo "usage: $0 [-r <rep_path>] [-p <pid> | -c <core>] [-s <solib_path>] [-a] <capsule> <executable>"
	echo "	-r <path to repository> : ie. /home1/kwarkentin/trunk"
	echo "	-p <pid>                : Pid of process to attach to.  If not specified,"
	echo "	                          this script will attach to the first 'ps' match."
	echo "	-c <core>               : Core file to examine instead of live process."
	echo "	-s <solib search path>  : Colon separated list of extra paths for solibs."
	echo "	-a                      : Do not set solib absolute prefix to capsule cstore."
	echo "	                          This is useful for Solaris 2.6 apps on Solaris 10."
	echo "	<capsule>                : Name of the capsule.  It is used to determine where"
	echo "	                          binaries will be found."
	echo "	<executable>             : Path to executable within capsule."
	echo
	echo "Note that all paths should be the path within the capsule.  That is,"
	echo "the should be relative to the cstore dir."
	echo
	echo "Example: $0 -r /home1/kwarkentin/release-3.0.7 -p 3057 my_virtual_capsule /usr/bin/some_app"
}

SET_ABSOLUTE_PREFIX=Y

if [ $# -lt 2 ] ; then
	usage
	exit 1
fi

. /etc/trigence/trigence.conf 2>/dev/null

while [ $# -ne 0 ] ; do
	case $1 in
	-c)
		CORE_FILE=$2
		shift
		;;
	-p)
		PID=$2
		shift
		;;
	-r)
		SRC_DIR=$2
		shift
		;;
	-a)
		SET_ABSOLUTE_PREFIX=N
		;;
	-s)
		SOLIB_SEARCH_PATH=$2
		shift
		;;
	*)
		if [ -z "$CAP" ] ; then
			CAP=$1
		elif [ -z "$EXE" ] ; then
			EXE=$1
		else
			echo "Invalid argument $1"
			usage
			exit 1
		fi
	esac
	shift
done

BINARY=`basename $EXE`
CAP_PATH=`$TRIGENCE_BIN/trictrl cprop cp`
SAP=$CAP_PATH/$CAP/cstore

if [ -z "$CORE_FILE" ] ; then
    if [ -z "$PID" ] ; then
    	PID=`ps -A | awk "/$BINARY/"'{print $1}'`
    fi

    if [ -z "$PID" ] ; then
    	echo "$0: No pid specified or found for $EXE.  Is it running?"
    	exit 1
    fi

    kill -0 $PID 2>/dev/null
    if [ $? -ne 0 ] ; then
    	echo "$0: No running process with pid $PID."
    	exit 1
    fi
    INI_FILE=$HOME/.$CAP.$BINARY.$PID.ini
else
    PID="$CORE_FILE"
    INI_FILE=$HOME/.$CAP.$BINARY.core.ini
fi

exec 5>$INI_FILE

if [ "$SET_ABSOLUTE_PREFIX" = "Y" ] ; then
	# Make sure we grab libs out of the capsule.
	echo "set solib-absolute-prefix $SAP" >&5
fi

if [ -n "$SOLIB_SEARCH_PATH" ] ; then
	for path in `echo $SOLIB_SEARCH_PATH | sed 's/:/ /g'` ; do
		if [ -z "$new_path" ] ; then
			new_path="$SAP$path"
		else
			new_path="$SAP$path:$new_path"
		fi
	done
	echo "set solib-search-path $new_path" >&5
fi

HOST=`uname`

# Calculate the base+offset for our libraries.  Only libtrig_runtime for now.
# Linux is easy because pmap shows the full path to the trigence libs.  Solaris we have
# to check the map inodes until we find what we're looking for.
for trig_lib in libtrig_runtime ; do
	case $HOST in
	SunOS)
		for addr_ino in `pmap $PID | grep 'r-x' | awk '/ino:/{print $1 ":" $5 }'` ; do
			ino=`echo $addr_ino | cut -d: -f3`
			lib_path=`find $SAP/trigence -mount -inum $ino -name "$trig_lib*" 2>/dev/null`
			if [ -n "$lib_path" ] ; then
				base_addr=0x`echo $addr_ino | cut -d: -f1`
				off=`/usr/ccs/bin/elfdump -c -N.text $lib_path | awk '/sh_addr:/{print $2}'`
				break
			fi
		done
		;;
	Linux)
		lib_addr=`pmap $PID | grep $trig_lib | awk '/r-xp/{print "0x"$1 " " $6}'`
		off=0x`objdump -h $SAP/trigence/lib/$trig_lib.so | awk '/\.text/{print $4}'`
		base_addr=`echo $lib_addr | cut -d' ' -f1`
		lib_path=`echo $lib_addr | cut -d' ' -f2`
		;;
	esac
	if [ -n "$base_addr" -a -n "$lib_path" ] ; then
		echo "add-symbol-file $lib_path $base_addr+$off" >&5
	fi
done

# If we didn't compile all our code with relative paths, none of this would be
# necessary.  This covers most of the source that libtrig_runtime uses.  On the bright
# side, 'directory' prepends so you can always add more.
if [ -n "$SRC_DIR" ] ; then
	echo -n "directory " >&5
	for path in kapi cfs2/lib upcall upcall/sys utils mgmt/events ; do
		echo -n "$SRC_DIR/cc/controller/$path:" >&5
	done
	case $HOST in
	SunOS)
		echo -n "$SRC_DIR/cc/controller/upcall/sys/solaris:" >&5
		echo -n "$SRC_DIR/cc/controller/upcall/sys/solaris/sparc64:" >&5
		;;
	Linux)
		echo -n "$SRC_DIR/cc/controller/upcall/sys/linux:" >&5
		echo -n "$SRC_DIR/cc/controller/upcall/sys/linux/i386:" >&5
		;;
	esac
	echo "$SRC_DIR/cc/common/src" >&5
fi

if [ -z "$CORE_FILE" ] ; then
    echo "attach $PID" >&5
fi

if [ -f $SAP/$EXE ] ; then
    gdb -x $INI_FILE $SAP/$EXE $CORE_FILE
else
    gdb -x $INI_FILE $EXE $CORE_FILE
fi

rm $INI_FILE
