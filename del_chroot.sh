#!/bin/sh

if [ $# -ne 1 ] ; then
	echo "usage: $0 TARGET"
	exit 1
fi

TARGET=$1
if [ ! -d $TARGET ] ; then
	echo $TARGET does not exist
	exit 1
fi
REALPATH=`(cd $TARGET ; pwd)`

if [ -z "$REALPATH" ] ; then
	echo "invalid target $TARGET"
	exit 1
fi

grep -Fv "$REALPATH/" /etc/fstab > /tmp/fstab.$$
diff -u /etc/fstab /tmp/fstab.$$

echo -n "These are the fstab changes. Good? (yes/no) "
read resp
if [ "$resp" != "yes" ] ; then
	echo exiting
	rm -f /tmp/fstab.$$
	exit 1
fi

for mount in home proc dev/pts var/cache/git ; do
	res=`umount $REALPATH/$mount 2>&1`
	if [ $? -ne 0 ] ; then
		if echo $res | grep -q 'not mounted$' ; then
			echo Warning: $REALPATH/$mount not mounted.
		else
			echo Failed to unmount $REALPATH/$mount.  Aborting.
			exit 1
		fi
	fi
done

mv /tmp/fstab.$$ /etc/fstab
rm -rf $REALPATH
