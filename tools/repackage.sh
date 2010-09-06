#!/bin/bash

unpack(){
	echo "Unpacking firmware..."

	echo Removing old files...
	rm -rf unpacked
	clean

	echo Removing 32 byte MD5 from beginning of original firmware...
	dd if=origfw/wdtvlive.bin of=origimg.tmp bs=32 skip=1c

	echo Unpacking...
	./cramfsck -x unpacked origimg.tmp

	clean
}

applyPatches(){
	for i in ./patches/* ; do
	  echo "Applying patch $i..."
	  patch -p0 $i >/dev/null
	done
}

applyFS(){
	echo "Copying filesystem modifications..."
	cp -rfv root/* unpacked/
}

repack(){
	echo "Repacking firmware..."

	echo Removing old files...
	clean

	if [ "$1" != "nomd5" ]; then
		echo Recreating md5sum.txt...
		cd unpacked
		rm -f md5sum.txt
		md5deep -rsl -o f . > ../deepmd5sum.tmp
		mv ../deepmd5sum.tmp md5sum.txt
		cd ../
	fi

	echo Making cramfs...
	./mkcramfs unpacked newimg.tmp

	echo Generating signature and adding to new firmware...

	sign newimg.tmp signature.tmp

	cat newimg.tmp signature.tmp > signedimg.tmp
	md5sum signedimg.tmp | dd bs=32 count=1 > signedimgmd5.tmp
	cat signedimgmd5.tmp signedimg.tmp > release/wdtvlive.bin

	echo -e "Original MD5:\n`md5sum origfw/wdtvlive.bin | cut -c 1-32`"
	echo -e "New MD5:\n`md5sum release/wdtvlive.bin | cut -c 1-32`"

	echo Clearing tmp files...
	clean
}

sign(){
	echo -ne "\xCE\xFA\xBE\xBA\x02\x00\x00\x00" > $2
	FS=`stat -c %s $1`
	xFS=`echo "ibase=10;obase=16; $FS" | bc | tr -d '\n'`
	wc=`echo $xFS | tr -d '\n' | wc -m`
	[ $wc -eq 7 ] && xFS="0$xFS"
	FS=""
	for i in 6 4 2 0 ; do
	   FS="$FS\x${xFS:$i:2}"
	done
	FS="$FS\x00\x00\x00\x00"
	echo -ne $FS | head -c 8 >> $2
}

clean(){
	rm -rf *.tmp
}

testRun(){
	echo "Testing firmware repackaging procedure..."
	unpack
	repack nomd5

	if [ `md5sum origfw/wdtvlive.bin | cut -c 1-32` = `md5sum release/wdtvlive.bin | cut -c 1-32` ]; then
		echo -e "\033[1;34mOriginal firmware MD5 matches repackaged firmware's MD5, everything looks good!\033[0m"
	else
		echo -e "\033[1;31mTest run failed, please review script output for any errors and fix.\033[0m"
	fi	
}

showmenu () {
	echo -e "\033[1m-----------------------------------------------\033[0m"
	echo -e "\033[1mPlease select an option and hit <enter>...     \033[0m"
	echo -e "\033[1m-----------------------------------------------\033[0m"
	echo -e "\033[1m1) Unpack firmware.\033[0m"
	echo -e "\033[1m2) Apply patches.\033[0m"
	echo -e "\033[1m3) Apply filesystem modifications.\033[0m"
	echo -e "\033[1m4) Repack firmware.\033[1m"
	echo -e "\033[1m5) Test run.\033[0m"
	echo -e "\033[1m6) Quit!\033[0m"
}

while [ 1 ] ; do
	showmenu
	read CHOICE
	case "$CHOICE" in
	"1")
	unpack
	;;
	"2")
	applyPatches
	;;
	"3")
	applyFS
	;;
	"4")
	repack
	;;
	"5")
	testRun
	;;
	"6")
	exit
	;;
	esac
done