#!/bin/bash
# name          : boot_backup
# desciption    : creates a backup image form boot device if updates ocure
# autor         : speefak ( itoss@gmx.de )
# licence       : (CC) BY-NC-SA
# version 	: 0.1
# notice 	:
# infosource	:
#
#------------------------------------------------------------------------------------------------------------
############################################################################################################
#######################################   define global variables   ########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------

 BootImageCountKeep=3
 BootImageStorageDir="/"

 BootImageName="$(hostname)-boot-"
 ProcessingDate=$(date '+%F-%H%M%S')
 BootDevice=$(mount -l | grep boot | cut -d " " -f1)
 BootImageList=$(find "$BootImageStorageDir" -maxdepth 1 -type f -name "$BootImageName*" | sort -u)
 
 RequiredPackets="bash sed awk sendmail postfix bind9-dnsutils"
 CheckMark="\033[0;32m\xE2\x9C\x94\033[0m"

#------------------------------------------------------------------------------------------------------------
############################################################################################################
########################################   set vars from options  ##########################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------

	OptionVarList="
		UpdateBootImage;-u
		CheckBootImage;-c
		Monochrome;-m
		ScriptInformation;-si
		HelpDialog;-h
	"

	# set entered vars from optionvarlist
	OptionAllocator=" "									# for option seperator "=" use cut -d "="
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	for InputOption in $(echo " $@" | sed 's/ -/\n-/g' ) ; do  				# | sed -e 's/-[a-z]/\n\0/g'
		for VarNameVarValue in $OptionVarList ; do
			VarName=$(echo "$VarNameVarValue" | cut -d ";" -f1)
			VarValue=$(echo "$VarNameVarValue" | cut -d ";" -f2)
			if [[ -n $(echo " $InputOption" | grep -w " $VarValue" 2>/dev/null) ]]; then
#				InputOption=$(sed 's/[ 0]*$//'<<< $InputOption)
				InputOption=$(sed 's/ $//g'<<< $InputOption)
				InputOptionValue=$(awk -F "$OptionAllocator" '{print $2}' <<< "$InputOption" )
				if [[ -z $InputOptionValue ]]; then
					eval $(echo "$VarName"="true")
				else
					eval $(echo "$VarName"='$InputOptionValue')
				fi
			fi
		done
	done
	IFS=$SAVEIFS

#------------------------------------------------------------------------------------------------------------
############################################################################################################
###########################################   fixed functions   ############################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------
load_color_codes () {
	Black='\033[0;30m'	&&	DGray='\033[1;30m'
	LRed='\033[0;31m'	&&	Red='\033[1;31m'
	LGreen='\033[0;32m'	&&	Green='\033[1;32m'
	LYellow='\033[0;33m'	&&	Yellow='\033[1;33m'
	LBlue='\033[0;34m'	&&	Blue='\033[1;34m'
	LPurple='\033[0;35m'	&&	Purple='\033[1;35m'
	LCyan='\033[0;36m'	&&	Cyan='\033[1;36m'
	LLGrey='\033[0;37m'	&&	White='\033[1;37m'
	Reset='\033[0m'
	# Use them to print in your required colours:
	# printf "%s\n" "Text in ${Red}red${Reset}, white and ${Blue}blue${Reset}."

	BG='\033[47m'
	FG='\033[0;30m'

	# parse required colours for sed usage: sed 's/status=sent/'${Green}'status=sent'${Reset}'/g' |\
	if [[ $1 == sed ]]; then
		for ColorCode in $(cat $0 | sed -n '/^load_color_codes/,/FG/p' | tr "&" "\n" | grep "='"); do
			eval $(sed 's|\\|\\\\|g' <<< $ColorCode)						# sed parser '\033[1;31m' => '\\033[1;31m'
		done
	fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
usage() {
	printf " iptables-blacklist version: $Version | script location $basename $0\n"
	clear
	printf "\n"
	printf " Usage: $(basename $0) <options> "
	printf "\n"
	printf " -h		=> (h)elp dialog \n"
	printf " -u		=> (u)pdate boot image \n"
	printf " -c		=> (c)heck boot image \n"
	printf " -m		=> (m)onochrome output \n"
	printf " -si		=> (s)how script (i)nformation \n"
	printf  "\n${Red} $1 ${Reset}\n"
	printf "\n"
	exit
}
#------------------------------------------------------------------------------------------------------------------------------------------------
script_information () {
	printf "\n"
	printf " Scriptname: $ScriptName\n"
	printf " Version:    $Version \n"
	printf " Location:   $(pwd)/$ScriptName\n"
	printf " Filesize:   $(ls -lh $0 | cut -d " " -f5)\n"
	printf "\n"
	exit 0
}
#------------------------------------------------------------------------------------------------------------------------------------------------
check_for_required_packages () {

	InstalledPacketList=$(dpkg -l | grep ii | awk '{print $2}' | cut -d ":" -f1)

	for Packet in $RequiredPackets ; do
		if [[ -z $(grep -w "$Packet" <<< $InstalledPacketList) ]]; then
			MissingPackets=$(echo $MissingPackets $Packet)
		fi
	done

	# print status message / install dialog
	if [[ -n $MissingPackets ]]; then
		printf  "missing packets: \e[0;31m $MissingPackets\e[0m\n"$(tput sgr0)
		read -e -p "install required packets ? (Y/N) "			-i "Y" 		InstallMissingPackets
		if   [[ $InstallMissingPackets == [Yy] ]]; then

			# install software packets
			sudo apt update
			sudo apt install -y $MissingPackets
			if [[ ! $? == 0 ]]; then
				exit
			fi
		else
			printf  "programm error: $LRed missing packets : $MissingPackets $Reset\n\n"$(tput sgr0)
			exit 1
		fi
	else
		printf "$LGreen all required packets detected$Reset\n"
	fi
}
#------------------------------------------------------------------------------------------------------------------------------------------------
check_boot_device () {

	# check for existing seprate boot device
	printf " Check for separate boot partition "
	if [[ -z $BootDevice ]]; then
		usage " no separate boot device detected"
	else
		printf "$CheckMark \n"
	fi
	
	#  check for /boot changes / Skip md5sum check if noch Bootimage exists
	if [[ -n $BootImageList ]]; then
		printf " Calculate checksums "
		Md5sumBootPartition=$(md5sum $BootDevice)
		Md5sumBootImage=$(md5sum $( tail -n 1 <<< "$BootImageList"))
		printf "$CheckMark \n"
	else
		printf " Calculate checksums skipped, no Backupimage found \n"
	fi

	# compare checksums and set UpdateBootImage parameter
	if [[ $( cut -d " " -f1 <<< $Md5sumBootPartition) !=  $(cut -d " " -f1 <<< $Md5sumBootImage) ]]; then
		UpdateBootImage=true
	else
		UpdateBootImage=
	fi

	# print checksums
	printf "\n  $Md5sumBootPartition \n"
	printf "  $Md5sumBootImage \n\n"
}
#------------------------------------------------------------------------------------------------------------------------------------------------
update_boot_image () {

	printf " create backup image : /boot => $BootImageStorageDir$BootImageName$ProcessingDate.img \n"
	dd if="$BootDevice" of="$BootImageStorageDir$BootImageName$ProcessingDate.img" 
	printf "\n"

}
#------------------------------------------------------------------------------------------------------------------------------------------------
clear_boot_image_storage () {

	BootImageList=$(find "$BootImageStorageDir" -maxdepth 1 -type f -name "$BootImageName*" | sort -u)
	for i in $(tac <<< "$BootImageList") ; do
		Counter=$(($Counter+1))
		if [[ $Counter -gt $BootImageCountKeep ]]; then
			printf "$Red delete $i $Reset\n"
			rm $i
			continue
		fi
		printf "$Green keep   $i $Reset\n"
	done
}
#------------------------------------------------------------------------------------------------------------------------------------------------
############################################################################################################
#############################################   start script   #############################################
############################################################################################################
#------------------------------------------------------------------------------------------------------------------------------------------------

	# check help dialog
	if [[ -n $HelpDialog ]] || [[ -z $1 ]]; then usage "help dialog" ; fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# check for monochrome output
	if [[ -z $Monochrome ]]; then
		load_color_codes
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# check for script information
	if [[ -n $ScriptInformation ]]; then script_information ; fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# check for root permission
	if [ "$(whoami)" = "root" ]; then echo "";else echo "Are You Root ?";exit 1;fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# check boot image
	if [[ -n $CheckBootImage ]]; then
		check_boot_device
		exit
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	# update boot image
	if [[ -n $UpdateBootImage ]]; then
		UpdateBootImage=
		check_boot_device
		if [[ $UpdateBootImage == true ]]; then
			update_boot_image
		else
			printf " no changes detected \n\n"
		fi
	fi

#------------------------------------------------------------------------------------------------------------------------------------------------

	clear_boot_image_storage

#------------------------------------------------------------------------------------------------------------------------------------------------

exit 0









