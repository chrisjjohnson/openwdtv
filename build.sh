#!/bin/bash
#  _____             _ _ _ ____  _____ _____ 
# |     |___ ___ ___| | | |    \|_   _|  |  |
# |  |  | . | -_|   | | | |  |  | | | |  |  |
# |_____|  _|___|_|_|_____|____/  |_|  \___/ 
#       |_| http://openwdtv.org


#############
## OPTIONS ##
#############
# Set default menu type
var_menutype="basic"
# Set maximum firmware size
var_maxfwsize=94371840
# Delete firmware from release folder on any error
var_autodeleteinvalidfw=1
# Automatically download new approved.list (change to 0 if you want to use custom firmware)
var_autoapproved=1

unpackFirmware(){
    fw_line=`grep -e "\b$1,.*\b" approved.list`
    fw_version=`echo $fw_line | awk -F ',' '{ print $3 }'`
    fw_file=`basename $fw_url`
    fw_orig=`find origfw/$fw_version -name "wdtvlive.bin"`

    printMsg "Clearing old files..."
    rm -rf unpacked
    deleteTmpFiles

    printMsg "Extracting firmware archive..."
    unzip -o origfw/$fw_file -d origfw/$fw_version
    
    printMsg "Stripping 32 byte MD5 and 16 byte signature from original firmware and outputting..."
    dd if=$fw_orig of=origimg.tmp bs=16 skip=2 count=$(($(stat -c %s $fw_orig)/16-3))

    printMsg "Extracting cramfs..."

    if [ $cygwin -eq 1 ]; then
        ./tools/cramfsck-cygwin.exe -x unpacked origimg.tmp
    else
        if [ "$architecture" != "x86_64" ] && [ "$architecture" != "ia64" ]; then
            ./tools/cramfsck32 -x unpacked origimg.tmp
        else
            ./tools/cramfsck64 -x unpacked origimg.tmp
        fi
    fi

    if [ "$2" != "selftest" ]; then
        printMsg "Removing original init.d files..."
        rm -rf unpacked/etc/init.d/*
    fi

    deleteTmpFiles

    printSuccess "Firmware unpacked"
    return 0
}

applyPatches(){
    for i in patches/*.diff ; do
        printMsg "Applying patch $i..."
        patch -p0 $i >/dev/null
    done
}

applyFS(){
    printMsg "Copying filesystem modifications..."
    cp -r --remove-destination root/* unpacked/
    printSuccess "Filesystem modifications applied"
}

repackFirmware(){
    fw_line=`grep -e "\b$1,.*\b" approved.list`
    fw_id=`echo $fw_line | awk -F ',' '{ print $1 }'`
    fw_version=`echo $fw_line | awk -F ',' '{ print $3 }'`
    fw_orig=`find origfw/$fw_version -name "wdtvlive.bin"`
    
    printMsg "Repacking firmware..."

    deleteTmpFiles

    if [ "$2" != "selftest" ]; then
        printMsg "Recreating md5sum.txt..."
        cd unpacked
        rm -f md5sum.txt
        find . -type f -exec md5sum {} \; > ../md5sum.tmp
        mv ../md5sum.tmp md5sum.txt
        cd ../
        printMsg "Updating timestamps..."
        find unpacked/* -type f -exec touch {} \;
    fi

    printMsg "Making cramfs..."

    if [ $cygwin -eq 1 ]; then
        ./tools/mkcramfs-cygwin.exe unpacked newimg.tmp
    else
        if [ "$architecture" != "x86_64" ] && [ "$architecture" != "ia64" ]; then
            ./tools/mkcramfs32 unpacked newimg.tmp
        else
            ./tools/mkcramfs64 unpacked newimg.tmp
        fi
    fi

    printMsg "Generating signature and adding to new firmware..."
    sign newimg.tmp signature.tmp

    cat newimg.tmp signature.tmp > signedimg.tmp
    md5sum signedimg.tmp | dd bs=32 count=1 of=signedimgmd5.tmp &> /dev/null
    cat signedimgmd5.tmp signedimg.tmp > release/wdtvlive.bin

    printMsg "Original MD5: `md5sum $fw_orig | cut -c 1-32`"
    printMsg "New MD5: `md5sum release/wdtvlive.bin | cut -c 1-32`"

    deleteTmpFiles

    printSuccess "Firmware repacked"
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

deleteTmpFiles(){
    printMsg "Removing temp files..."
    rm -rf *.tmp
}

createDirs(){
    for dir in unpacked release origfw patches root; do
        if [ ! -d $dir ]; then
        printMsg "Creating directory: $dir..."
        mkdir $dir
        fi
    done
}

downloadApprovedList(){
    printMsg "Attemping to download latest approved.list..."
    if wget --no-check-certificate -q -O approved.list https://github.com/drewzh/openwdtv/raw/master/approved.list ; then
        printSuccess "approved.list downloaded"
        return 0
    else
        printError "Error downloading approved.list, aborting..."
        return 1
    fi
}

selectFirmware(){
    printFirmwareMenu
    read var_fwselect
    return $var_fwselect
}

downloadFirmware(){
    fw_line=`grep -e "\b$1,.*\b" approved.list`
    fw_url=`echo $fw_line | awk -F ',' '{ print $4 }'`
    fw_file=`basename $fw_url`
    fw_md5=`echo $fw_line | awk -F ',' '{ print $5 }'`
    
    if [ -e origfw/$fw_file ]; then
        if [ "`md5sum origfw/$fw_file | cut -c 1-32`" = "$fw_md5" ]; then
            printSuccess "Firmware already downloaded, continuing..."
            return 0
        else
            printError "Downloaded firmware is corrupt, would you like to re-download?"
            read -n 1 var_dlcheck
            [[ ! $var_dlcheck = [yY] ]] && return 1
        fi
    fi
    printMsg "Downloading firmware, please wait..."

    if wget -O origfw/$fw_file $fw_url && [ "`md5sum origfw/$fw_file | cut -c 1-32`" = "$fw_md5" ]; then
        printSuccess "Firmware downloaded successfully"
        return 0
    else
        printError "Error downloading firmware, aborting..."
        rm -f origfw/$fw_file
        return 1
    fi
}

selfTest(){
    printMsg "Select a firmware to run self test procedure on..."
    selectFirmware
    fwid=$?
    
    fw_line=`grep -e "\b$fwid,.*\b" approved.list`
    fw_id=`echo $fw_line | awk -F ',' '{ print $1 }'`
    fw_version=`echo $fw_line | awk -F ',' '{ print $3 }'`
    fw_orig=`find origfw/$fw_version -name "wdtvlive.bin"`
    
    downloadFirmware $fwid
    unpackFirmware $fwid selftest
    repackFirmware $fwid selftest

    if [ "`md5sum $fw_orig | cut -c 1-32`" = "`md5sum release/wdtvlive.bin | cut -c 1-32`" ]; then
        printSuccess "Original firmware MD5 matches repackaged firmware's MD5, everything looks good!"
        return 0
    else
        printError "Test run failed, please review script output for any errors and fix."
        return 1
    fi
}

checkFirmwareSize(){
    [ `stat -c %s release/wdtvlive.bin` -le $var_maxfwsize ] && return 0 || return 1
}

deleteInvalidFirmware(){
    if [ $var_autodeleteinvalidfw -eq 1 ]; then
        printError "Deleting invalid firmware from release folder..."
        rm -f release/wdtvlive.bin
    fi
}

wizard(){
    printMsg "Starting wizard..."

    printMsg "Please select a firmware to modify:"
    selectFirmware
    fwid=$?
    if [ $fwid -eq 0 ]; then
        printError "No firmware selected, aborting..."
        return 1
    fi

    downloadFirmware $fwid
    if [ $? -ne 0 ]; then
        printError "Error downloading firmware, aborting..."
        return 1
    fi

    unpackFirmware $fwid
    if [ $? -ne 0 ]; then
        printError "Failed to unpack firmware, aborting...."
        return 1
    fi
    
    # Apply firmware modifications
    #applyPatches
    applyFS

    repackFirmware $fwid
    if [ $? -ne 0 ]; then
        printError "Failed to repack firmware, aborting..."
        return 1
    fi

    checkFirmwareSize
    if [ $? -ne 0 ]; then
        printError "Firmware exceeds maximum file size of 
$var_maxfwsize bytes, aborting..."
        return 1
    fi

    printSuccess "Successfully repackaged firmware and output to release folder, have a nice day :)"
    return 0
}

printBanner(){
    printMsg " _____             _ _ _ ____  _____ _____ "
    printMsg "|     |___ ___ ___| | | |    \|_   _|  |  |"
    printMsg "|  |  | . | -_|   | | | |  |  | | | |  |  |"
    printMsg "|_____|  _|___|_|_|_____|____/  |_|  \___/ "
    printMsg "      |_| http://openwdtv.org              "
}

printFirmwareMenu(){
    while read curline; do
        printMsg $curline | awk -F ',' '{print $1") "$3" ["$2"]"}'
    done < approved.list
}

printMsg(){
    echo -e "\033[1m$1\033[0m"
}

printError(){
    echo -e "\033[1;31m$1\033[0m"
}

printSuccess(){
    echo -e "\033[1;32m$1\033[0m"
}

basicMenu () {
    printMsg "+-----------------------------------------+"
    printMsg "| Please select an option and hit <enter> |"
    printMsg "+-----------------------------------------+"
    printMsg "| 1) Start wizard                         |"
    printMsg "| 2) Switch to advanced mode              |"
    printMsg "| 3) Quit                                 |"
    printMsg "+-----------------------------------------+"
}

advancedMenu () {
    printMsg "+-----------------------------------------+"
    printMsg "| Please select an option and hit <enter> |"
    printMsg "+-----------------------------------------+"
    printMsg "| 1) Download firmware                    |"
    printMsg "| 2) Unpack firmware                      |"
    printMsg "| 3) Apply patches                        |"
    printMsg "| 4) Apply filesystem modifications       |"
    printMsg "| 5) Repack firmware                      |"
    printMsg "| 6) Self test                            |"
    printMsg "| 7) Switch to basic mode                 |"
    printMsg "| 8) Quit                                 |"
    printMsg "+-----------------------------------------+"
}

########################
## SCRIPT ENTRY POINT ##
########################
# Is running in cygwin?
cygwin=`uname -a | grep -i "CYGWIN" &> /dev/null && echo 1 || echo 0`
# Get system architecture
architecture=`uname -m`
# Create any missing directories
createDirs
# Make sure we have the latest list of approved firmwares
[ $var_autoapproved -eq 1 ] && downloadApprovedList

while [ 1 ]; do
    printBanner
    case $var_menutype in
    "basic")
        basicMenu
        read CHOICE
        case "$CHOICE" in
        "1")
            wizard
            [ $? -ne 0 ] && deleteInvalidFirmware
            ;;
        "2")
            var_menutype="advanced"
            continue
            ;;
        "3")
            exit
            ;;
        esac
    ;;
    "advanced")
        advancedMenu
        read CHOICE
        case "$CHOICE" in
        "1")
            selectFirmware
            downloadFirmware $?
            ;;
        "2")
            selectFirmware
            unpackFirmware $?
            ;;
        "3")
            applyPatches
            ;;
        "4")
            applyFS
            ;;
        "5")
            selectFirmware
            repackFirmware $?
            [ $? -ne 0 ] && deleteInvalidFirmware
            ;;
        "6")
            selfTest
            [ $? -ne 0 ] && deleteInvalidFirmware
            ;;
        "7")
            var_menutype="basic"
            continue
            ;;
        "8")
            exit
            ;;
        esac
    esac
done
