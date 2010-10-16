#!/bin/sh
#
# Copyright (c) 2010 The Chromium OS Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# This script can change key (usually developer keys) and kernel config
# of a kernels on SSD.

SCRIPT_BASE="$(dirname "$0")"
. "$SCRIPT_BASE/common.sh"
load_shflags || exit 1

# Constants used by DEFINE_*
VBOOT_BASE='/usr/share/vboot'
DEFAULT_KEYS_FOLDER="$VBOOT_BASE/devkeys"
DEFAULT_BACKUP_FOLDER='/mnt/stateful_partition/backups'

# DEFINE_string name default_value description flag
DEFINE_string image "/dev/sda" "Path to device or image file" "i"
DEFINE_string keys "$DEFAULT_KEYS_FOLDER" "Path to folder of dev keys" "k"
DEFINE_boolean remove_rootfs_verification \
  $FLAGS_FALSE "Modify kernel boot config to disable rootfs verification" ""
DEFINE_string backup_dir \
  "$DEFAULT_BACKUP_FOLDER" "Path of directory to store kernel backups" ""
DEFINE_boolean debug $FLAGS_FALSE "Provide debug messages" "d"

# Parse command line
FLAGS "$@" || exit 1
eval set -- "$FLAGS_ARGV"

# Globals
# ----------------------------------------------------------------------------
set -e

# a log file to keep the output results of executed command
EXEC_LOG="$(make_temp_file)"

# Functions
# ----------------------------------------------------------------------------
# Reports error message and exit(1)
err_die() {
  echo "ERROR: $*" 1>&2
  exit 1
}

# Returns true if we're running in debug mode
is_debug_mode() {
  [ "$FLAGS_debug" = $FLAGS_TRUE ]
}

# Prints messages (in parameters) in debug mode
debug_msg() {
  if is_debug_mode; then
    echo "DEBUG: $*" 1>&2
  fi
}

# Removes rootfs verification from kernel boot parameter
remove_rootfs_verification() {
  echo "$*" | sed '
    s|dm_verity[^ ]\+||g
    s| ro | rw |
    s|verity /dev/sd%D%P /dev/sd%D%P ||
    s| root=/dev/dm-0 | root=/dev/sd%D%P |
    s|dm="[^"]\+" ||'
}

# Wrapped version of dd
mydd() {
  # oflag=sync is safer, but since we need bs=512, syncing every block would be
  # very slow.
  dd "$@" >"$EXEC_LOG" 2>&1 ||
    err_die "Failed in [dd $@], Message: $(cat "$EXEC_LOG")"
}

# Prints a more friendly name from kernel index number
cros_kernel_name() {
  case $1 in
    2)
      echo "Kernel A"
      ;;
    4)
      echo "Kernel B"
      ;;
    *)
      err_die "unknown kernel index: $1"
  esac
}

# Resigns a kernel on SSD or image.
resign_ssd_kernel() {
  # bs=512 is the fixed block size for dd and cgpt
  local bs=512
  local ssd_device="$1"

  # reasonable size for current kernel partition
  local min_kernel_size=32000
  local max_kernel_size=65536
  local resigned_kernels=0

  for kernel_index in 2 4; do
    local old_blob="$(make_temp_file)"
    local new_blob="$(make_temp_file)"
    local name="$(cros_kernel_name $kernel_index)"

    debug_msg "Probing $name information"
    local offset size
    offset="$(partoffset "$ssd_device" "$kernel_index")" ||
      err_die "Failed to get partition $kernel_index offset from $ssd_device"
    size="$(partsize "$ssd_device" "$kernel_index")" ||
      err_die "Failed to get partition $kernel_index size from $ssd_device"
    if [ ! $size -gt $min_kernel_size ]; then
      echo "WARNING: $name seems too small ($size), ignored."
      continue
    fi
    if [ ! $size -le $max_kernel_size ]; then
      echo "WARNING: $name seems too large ($size), ignored."
      continue
    fi

    debug_msg "Reading $name from partition $kernel_index"
    mydd if="$ssd_device" of="$old_blob" bs=$bs skip=$offset count=$size

    debug_msg "Checking if $name is valid"
    local old_kernel_config
    if ! old_kernel_config="$(dump_kernel_config "$old_blob" 2>"$EXEC_LOG")"
    then
      debug_msg "dump_kernel_config error message: $(cat "$EXEC_LOG")"
      echo "WARNING: $name: no kernel boot information, ignored."
      continue
    fi

    debug_msg "Decide and prepare signing parameters"
    local resign_command
    # TODO(hungte) $KERNEL_KEYBLOCK and $new_kernel_config should also be
    # quoted, but quoting inside would cause extra quote... We should find some
    # better way to do this, for example using eval.
    if [ ${FLAGS_remove_rootfs_verification} = $FLAGS_TRUE ]; then
      local new_kernel_config_file="$(make_temp_file)"
      remove_rootfs_verification "$old_kernel_config" >"$new_kernel_config_file"
      resign_command="--config $new_kernel_config_file"
      debug_msg "New kernel config: $(cat $new_kernel_config_file)"
      echo "$name: Disabled rootfs verification."
    else
      resign_command="--vblockonly --keyblock $KERNEL_KEYBLOCK"
    fi

    debug_msg "Re-signing $name from $old_blob to $new_blob"
    debug_msg "Using key: $KERNEL_DATAKEY, command: $resign_command"
    vbutil_kernel \
      --repack "$new_blob" \
      $resign_command \
      --signprivate "$KERNEL_DATAKEY" \
      --oldblob "$old_blob" >"$EXEC_LOG" 2>&1 ||
      err_die "Failed to resign $name. Message: $(cat "$EXEC_LOG")"

    debug_msg "Creating new kernel image (vboot+code+config)"
    local new_kern="$(make_temp_file)"
    cp "$old_blob" "$new_kern"
    mydd if="$new_blob" of="$new_kern" conv=notrunc

    if is_debug_mode; then
      debug_msg "for debug purposes, check *.dbgbin"
      cp "$old_blob" old_blob.dbgbin
      cp "$new_blob" new_blob.dbgbin
      cp "$new_kern" new_kern.dbgbin
    fi

    debug_msg "Verifying new kernel and keys"
    vbutil_kernel \
      --verify "$new_kern" \
      --signpubkey "$KERNEL_PUBKEY" --verbose >"$EXEC_LOG" 2>&1 ||
      err_die "Failed to verify new $name. Message: $(cat "$EXEC_LOG")"

    debug_msg "Backup old kernel blob"
    local backup_date_time="$(date +'%Y%m%d_%H%M%S')"
    local backup_name="$(echo "$name" | sed 's/ /_/g; s/^K/k/')"
    local backup_file_name="${backup_name}_${backup_date_time}.bin"
    local backup_file_path="$FLAGS_backup_dir/$backup_file_name"
    if mkdir -p "$FLAGS_backup_dir" &&
      cp -f "$old_blob" "$backup_file_path"; then
      echo "Backup of $name is stored in: $backup_file_path"
    else
      echo "WARNING: Cannot create file in $FLAGS_backup_dir... Ignore backups."
    fi

    debug_msg "Writing $name to partition $kernel_index"
    mydd \
      if="$new_kern" \
      of="$ssd_device" \
      seek=$offset \
      bs=$bs \
      count=$size \
      conv=notrunc
    resigned_kernels=$(($resigned_kernels + 1))

    # Sometimes doing "dump_kernel_config" or other I/O now (or after return to
    # shell) will get the data before modification. Not a problem now, but for
    # safety, let's try to sync more.
    sync; sync; sync

    echo "$name: Re-signed with developer keys successfully."
  done
  return $resigned_kernels
}

# Main
# ----------------------------------------------------------------------------
main() {
  local num_signed=0
  # Check parameters
  KERNEL_KEYBLOCK="$FLAGS_keys/kernel.keyblock"
  KERNEL_DATAKEY="$FLAGS_keys/kernel_data_key.vbprivk"
  KERNEL_PUBKEY="$FLAGS_keys/kernel_subkey.vbpubk"

  debug_msg "Prerequisite check"
  ensure_files_exist \
    "$KERNEL_KEYBLOCK" \
    "$KERNEL_DATAKEY" \
    "$KERNEL_PUBKEY" \
    "$FLAGS_image" ||
    exit 1

  resign_ssd_kernel "$FLAGS_image" || num_signed=$?

  debug_msg "Complete."
  if [ $num_signed -gt 0 -a $num_signed -le 2 ]; then
    # signed 1 or two kernels
    echo "Successfully re-signed $num_signed kernel(s) on device $FLAGS_image".
  else
    err_die "Failed re-signing kernels."
  fi
}

main
