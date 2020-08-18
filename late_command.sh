#!/bin/bash
#
# late_command.sh v0.2-dev
#
# {SHORT_DESCRIPTION}
#
# Copyright (c) 2020 Tamás Tóth ({CONTACT_INFO}).
# Permission to copy and modify is granted under the MIT license.
#

## Configuration ##

# // Configure the script here.

# Paths and filenames.
root_dir="/root/.late_command"
logfile_name="late_command.log"

wget_url="https://example.com/debian10_generic.zip"
unzip_to="/"

swap_size="1G"

find_folders=(
	"/etc/skel/"
	"/home/"
)

# Permissions to be applied on find_folders[] above.
perm_folders=750
perm_ssh_folder=700
perm_files=640
perm_authorized_keys_file=600

# Note: You should never change 'perm_ssh_folder=700' and 'perm_authorized_keys_file=600',
#       because it may cause security risk on your system. However the option is there,
#       if you have to change it for some reason.

# // End of script configuration here.

## Global variables. ##

dependencies=(grep unzip wget)
installed_dependencies=()
fstab_entry_added=false
file_folder_removed=false
everything_done=true

# Shell colors.
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

timestamp=$(date "+%Y-%m-%d %H:%M:%S")
script_filename=$(basename $0)
zip_filename=$(basename $wget_url)
admin_users=$(getent group sudo | cut -d: -f4)

## Functions ##

function print_status()
{
	if [[ $? -eq 0 ]]
	then
		printf "$RESET[$GREEN%s$RESET]\n" "DONE"
	else
		printf "$RESET[$RED%s$RESET]\n" "FAILED"
		everything_done=false
	fi
}

## Main Script ##

export -f print_status
export RED
export GREEN
export RESET
export perm_folders
export perm_ssh_folder
export perm_files
export perm_authorized_keys_file

printf "$timestamp: Executing '$script_filename'.\n"

# Step 1: Creating root directory for the script.

if [[ ! -e $root_dir ]]
then
	printf "Creating '$root_dir' directory... "
	mkdir $root_dir; print_status
else
	printf "Note: '$root_dir' directory is already exists, skipping.\n"
fi

printf "\n"

# Redirecting output to the logfile.
exec 4<&1 5<&2 1>&2>&>(tee -a >(sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' >> $root_dir/$logfile_name))

# Step 2: Checking and installing dependencies.

printf "Running apt update... "
apt update > /dev/null 2>&1; print_status

printf "\n"

printf "Checking for dependencies:\n"
for package in "${dependencies[@]}"
do
	if ( ! command -v "$package" > /dev/null 2>&1 )
	then
		printf " [+] $package not found, installing... "
		apt install -y "$package" > /dev/null 2>&1; print_status
		installed_dependencies+=($package)
	fi
done

if [ ${#installed_dependencies[@]} -eq 0 ]
then
	printf " [Nothing to install]\n"
fi

printf "\n"

# Step 3: Creating swapfile.

printf "Creating swapfile:\n"

if [[ ! -f "/var/swap" ]]
then
	printf " Pre-allocating $swap_size disk space for the swapfile... "
	fallocate -l $swap_size /var/swap > /dev/null 2>&1; print_status

	printf " Fixing the swapfile's permissions... "
	chmod 600 /var/swap > /dev/null 2>&1; print_status

	printf " Setting up the swap area... "
	mkswap /var/swap > /dev/null 2>&1; print_status

	printf " Enabling the swapfile... "
	swapon /var/swap > /dev/null 2>&1; print_status
else
	printf " Swapfile '/var/swap' is already exists, skipping.\n"
fi

if ( ! grep -q '/var/swap' /etc/fstab )
then
	printf " Adding swapfile entry to '/etc/fstab'... "
	echo '/var/swap none swap sw 0 0' >> /etc/fstab; print_status
else
	printf " Swapfile entry is already added to '/etc/fstab', skipping.\n"
fi

printf "\n"

# Step 4: Adding custom entries to '/etc/fstab'

printf "Adding custom entries to '/etc/fstab':\n"

if ( ! grep -q '/proc' /etc/fstab )
then
	printf " Setting up mount option 'hidepid=2' on '/proc'... "
	echo 'proc  /proc  proc  defaults,hidepid=2  0 0' >> /etc/fstab; print_status
	fstab_entry_added=true
fi

if ( ! grep -q '/run/shm' /etc/fstab )
then
	printf " Setting up mount option 'tmpfs,noexec,nosuid' on '/run/shm'... "
	echo 'tmpfs  /run/shm  tmpfs  defaults,noexec,nosuid  0 0' >> /etc/fstab; print_status
	fstab_entry_added=true
fi

if [ $fstab_entry_added = false ]
then
	printf " Custom entries are already added to fstab, skipping...\n"
fi

printf "\n"

# Step 5: Downloading and extracting ZIP file.

printf "Downloading ZIP file '$zip_filename'... "
wget -q --no-check-certificate $wget_url -O $root_dir/$zip_filename; print_status

printf "Extracting ZIP file to '$unzip_to'... "
unzip -qq -o $root_dir/$zip_filename -d $unzip_to > /dev/null 2>&1; print_status
printf "\n"

# Step 6: Copying content of '/admin_skel/' to administrators' home directories
#         and fixing ownerships.

for user in ${admin_users[*]}
do
	printf "Copying admin skeleton's content to $user's home directory... "
	cp -R $root_dir/admin_skel/. /home/$user/ > /dev/null 2>&1; print_status
	printf "Fixing ownership of $user's home directory... "
	chown -R $user:$user /home/$user/ > /dev/null 2>&1; print_status
done

printf "\n"

# Step 7: Applying pre-defined permissions on find_folders[].

printf "Applying pre-defined permissions on selected folders:\n"

for folder in ${find_folders[*]}
do
	find $folder -mindepth 1 -name "lost+found" -prune -o -name "keyhelp" -prune -o -type d -exec bash -c \
	'
		if [[ ! {} =~ ".ssh" ]]
		then
			printf " [D] {} :: chmod $perm_folders... "
			chmod $perm_folders {} > /dev/null 2>&1; print_status
		else
			printf " [D] {} :: chmod $perm_ssh_folder... "
			chmod $perm_ssh_folder {} > /dev/null 2>&1; print_status
		fi
	' \;

	find $folder -name "lost+found" -prune -o -name "keyhelp" -prune -o -type f -exec bash -c \
	'
		if [[ ! {} =~ "authorized_keys"* ]]
		then
			printf " [F] {} :: chmod $perm_files... "
			chmod $perm_files {} > /dev/null 2>&1; print_status
		else
			printf " [F] {} :: chmod $perm_authorized_keys_file... "
			chmod $perm_authorized_keys_file {} > /dev/null 2>&1; print_status
		fi
	' \;
done

printf "\n"

# Step 8: Finishing; removing unnecessary packages, files and directories; printing out status messages.

if [ ! ${#installed_dependencies[@]} -eq 0 ]
then
	printf "Removing unnecessary packages:\n"
	for package in "${installed_dependencies[@]}"
	do
		printf " [-] $package has been installed during dependency check, removing... "
		apt autoremove -y --purge "$package" > /dev/null 2>&1; print_status
	done
fi

printf "Removing unnecessary files and directories:\n"

if [[ -f /usr/src/csf.tgz ]]
then
	printf " Removing '/usr/src/csf.tgz' file... "
	rm /usr/src/csf.tgz > /dev/null 2>&1; print_status
	file_folder_removed=true
fi

if [[ -e /usr/src/csf ]]
then
	printf " Removing '/usr/src/csf' directory... "
	rm -r /usr/src/csf > /dev/null 2>&1; print_status
	file_folder_removed=true
fi

if [ $file_folder_removed = false ]
then
	printf " [Nothing to remove]\n"
fi

printf "\n"

if [ $everything_done = true ]
then
	printf "Everything went well during execution of '$script_filename'. Your system has been pre-configured and ready to use.\n"
else
	printf "$RED!! %s $RESET-- %s\n" "Something has been FAILED during execution of '$script_filename'." "Please check the logfile for more informations!"
fi

printf "Logfile has been written to '$root_dir/$logfile_name'.\n\n"
