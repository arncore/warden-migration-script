#!/bin/sh

POOL=""
RENAME_JAILS=0
PATCH_FILE_PATH=""
SINGLE_JAIL_NAME=""
IOCAGE_JAILS_PATH="/mnt/iocage/jails"

migrate_jail() {
    local $jail_name="$1"
    echo "Migrating $jail_name"
    
    if migrate_warden.py -v -j "$jail_name" -p "$POOL"; then
        echo "Done migrating $jail_name"
    else
        echo "Failed to migrate $jail_name"
        echo "Exiting..."
        exit 1
    fi
}

rename_jail() {
    local new_jail_name="$2"
    local jail_name="$1"
    
    echo "Renaming $jail_name to $new_jail_name"
    
    if iocage rename "$jail_name" "$new_jail_name"; then
        echo "Renaming successful."
    else
        echo "Renaming failed."
        exit 1
    fi
}

apply_patch_to_jail_config() {
    local $new_jail_name="$1"
    echo "Applying patch file to $new_jail_name config.json"
    
    current_jail_config_file="$IOCAGE_JAILS_PATH/$new_jail_name/config.json"
    current_jail_old_config_file="$IOCAGE_JAILS_PATH/$new_jail_name/config.json.old"
    
    echo "Backing up old $new_jail_name config.json..."
    mv "$current_jail_config_file" "$current_jail_old_config_file"
    
    patch "$current_jail_old_config_file" -i "$PATCH_FILE_PATH" -o "$current_jail_config_file"
    
    if [ $? -eq 0 ]; then
        echo "Patched old config successfully."
        echo "$current_jail_config_file is ready."
    else
        echo "Failed to patch config.json for $new_jail_name"
        echo "Restoring old config..."
        mv "$current_jail_old_config_file" "$current_jail_config_file"
        exit 1
    fi
}

fix_config_mac_addr() {
    
    current_jail_config_file="$IOCAGE_JAILS_PATH/$new_jail_name/config.json"
    current_jail_old_config_file="$IOCAGE_JAILS_PATH/$new_jail_name/config.json.old"
    
    echo "Fixing MAC address in $current_jail_config_file"
    
    if ! [ -f "$current_jail_config_file" ]; then
        echo "Cannot find $current_jail_config_file"
        exit 1
    fi
    
    mac=$(cat "$current_jail_config_file" | jq -r '.vnet0_mac')
    
    echo "Old MAC: $mac"
    
    new_mac=$(echo "$mac" | sed s/://g )
    
    remainder="$new_mac"
    upper_mac="${remainder%%,*}"; lower_mac="${remainder#*,}"
    
    set +e
    lower_mac_dec=$( printf "%d\n" "0x$lower_mac" ) # to convert to decimal
    lower_mac_dec=$((lower_mac_dec+1)) # add one
    new_lower_mac=$( printf "%x" $lower_mac_dec ) # to convert to hex again
    set -e
    
    new_mac="$upper_mac,$new_lower_mac"
    
    set +e
    temp_file="$IOCAGE_JAILS_PATH/$new_jail_name/config.json.temp"
    jq --arg var "$new_mac" '.vnet0_mac = $var' "$current_jail_config_file" > "$temp_file"
    mv "$temp_file" "$current_jail_config_file"
    set -e
    
    echo "New MAC: $new_mac"
    
}

run_all_migrations() {
    for i in "$WARDEN_JAILS_PATH"/* ; do
        if [ -d "$i" ]; then
            jail_name=$(printf -- '%s\n' "${i##*/}")
            
            migrate_jail $jail_name
            
            new_jail_name="$jail_name"
            if [ $RENAME_JAILS -eq 1 ]; then
                
                new_jail_name="io_${jail_name}"
                
                rename_jail $jail_name $new_jail_name
            fi
            
            apply_patch_to_jail_config $new_jail_name
            
            fix_config_mac_addr $new_jail_name
            
            echo "Done migrating $jail_name"
        fi
    done
}

run_single_migration() {
    jail_name=$SINGLE_JAIL_NAME
    
    migrate_jail $jail_name
    
    new_jail_name="$jail_name"
    if [ $RENAME_JAILS -eq 1 ]; then
        
        new_jail_name="io_${jail_name}"
        
        rename_jail $jail_name $new_jail_name
    fi
    
    apply_patch_to_jail_config $new_jail_name
    
    fix_config_mac_addr $new_jail_name
    
    echo "Done migrating $jail_name"
}

main () {
    if [ "$POOL" = "" ]; then
        echo "Provide the pool name where your old jails are stored. Use -p."
        exit 1
    fi
    
    if [ "$PATCH_FILE_PATH" = "" ]; then
        echo "Provide the config.json patch file. Use -f."
        exit 1
    fi
    
    WARDEN_JAILS_PATH="/mnt/$POOL/jails"
    
    if [ "$SINGLE_JAIL_NAME" = "" ]; then
        run_all_migrations
    else
        run_single_migration
    fi
}

print_help() {
    echo "Usage: cmd [-rj] -p <pool_name> -f <patch_file>"
    echo "-r    Rename jails to format -> io_\${prev_jail_name}"
    echo "-j    Singular jail name to migrate"
    echo "-p    Pool name to migrate from assuming it's in /mnt/\${pool_name}/jails"
    echo "-f    Patch file for iocage config.json. The old config will be renamed to config.json.old"
    echo "-h    This help message"
}

while getopts "hp:j:f:r" opt; do
    case ${opt} in
        p ) POOL="$OPTARG"
        ;;
        r ) RENAME_JAILS=1
        ;;
        f ) PATCH_FILE_PATH="$OPTARG"
        ;;
        j ) SINGLE_JAIL_NAME="$OPTARG"
        ;;
        h ) print_help
        ;;
        \? ) print_help
        ;;
        : ) echo "Invalid option: $OPTARG requires an argument" 1>&2
        print_help
        ;;
    esac
done

main


