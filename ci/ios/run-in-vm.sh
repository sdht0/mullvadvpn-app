# This takes the following positional arguments 
# 1. tart VM name
# 2. Script to execute in the VM
# 3. Passthrough directory paths, formatted like "$guest_mount_name:$host_dir_path"
#
# The script expects that with the current SSH agent, it's possible to SSH into
# the `admin` user on the VM without any user interaction. The script will
# bring the VM up, execute the specified script via SSH and shut down the VM.
#
# The script returns the exit code of the SSH command.

set -o pipefail

VM_NAME=${1:?"No VM name provided"}
SCRIPT=${2:?"No script provided"}
SHARED_DIR=${3:?"No passthrough provided"}

tart run --no-graphics "--dir=${SHARED_DIR}" "$VM_NAME" &
vm_pid=$!
# apparently, there's a difference between piping into zsh like this and doing
# a <(echo $SCRIPT).
echo "$SCRIPT" | ssh admin@$(tart ip "$VM_NAME") zsh /dev/stdin
script_status=$?

kill $vm_pid
exit $script_status
