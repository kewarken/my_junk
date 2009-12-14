#!/bin/sh

EXTRADEBS="sudo fakeroot build-essential debhelper less"

if [ $# -lt 2 ] ; then
	echo "usage: $0 SUITE TARGET [MIRROR]"
	exit 1
fi

SUITE=$1
TARGET=$2
if [ ! -d $TARGET ] ; then
	mkdir -p $TARGET
else
	echo "Cowardly refusing to debootstrap existing directory"
	exit 1
fi

REALPATH=`(cd $TARGET ; pwd)`

if [ -z "$REALPATH" ] ; then
	echo "invalid target $TARGET"
	exit 1
fi

if ! debootstrap $SUITE $TARGET $3 ; then
	echo debootstrap failed...exiting
	exit 1
fi

echo "proc $REALPATH/proc proc defaults 0 0" >> /etc/fstab
echo "devpts $REALPATH/dev/pts devpts defaults 0 0" >> /etc/fstab
echo "/home $REALPATH/home none bind,rw 0 0" >> /etc/fstab
echo "/var/cache/git $REALPATH/var/cache/git none bind,rw 0 0" >> /etc/fstab
mount $REALPATH/proc
mount $REALPATH/home
mount $REALPATH/var/cache/git
mount $REALPATH/dev/pts
for file in passwd shadow group gshadow hosts sudoers; do
	cp /etc/$file $REALPATH/etc
done
cp /etc/skel/.bashrc $REALPATH/root
echo "$TARGET" > $REALPATH/etc/debian_chroot

if [ -n "$3" ] ; then
	echo "deb $3 $SUITE main contrib non-free" > $REALPATH/etc/apt/sources.list
	echo "deb-src $3 $SUITE main contrib non-free" >> $REALPATH/etc/apt/sources.list
fi

chroot $REALPATH apt-get update
chroot $REALPATH apt-get --force-yes -y install locales dialog
chroot $REALPATH mv /etc/locale.gen /etc/locale.gen.orig
chroot $REALPATH sed 's/^# en_/en_/' /etc/locale.gen.orig > /tmp/locale.gen
mv /tmp/locale.gen $REALPATH/etc
chroot $REALPATH locale-gen
chroot $REALPATH apt-get --force-yes -y install $EXTRADEBS
