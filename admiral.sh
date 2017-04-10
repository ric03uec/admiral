#!/bin/bash -e

###########################################################
#
# Shippable Enterprise Installer
#
# Supported OS: Ubuntu 14.04
# Supported bash: 4.3.11
###########################################################

# Global variables ########################################
###########################################################
readonly IFS=$'\n\t'
readonly ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly CONFIG_DIR="/etc/shippable"
readonly RUNTIME_DIR="/var/run/shippable"
readonly SERVICES_DIR="$ROOT_DIR/services"
readonly MIGRATIONS_DIR="$ROOT_DIR/migrations"
readonly POST_INSTALL_MIGRATIONS_DIR="$MIGRATIONS_DIR/post_install"
readonly SCRIPTS_DIR="$ROOT_DIR/common/scripts"
readonly LIB_DIR="$SCRIPTS_DIR/lib"
readonly LOGS_DIR="$RUNTIME_DIR/logs"
readonly TIMESTAMP="$(date +%Y_%m_%d_%H_%M_%S)"
readonly LOG_FILE="$LOGS_DIR/${TIMESTAMP}_logs.txt"
readonly REMOTE_SCRIPTS_DIR="$SCRIPTS_DIR/remote"
readonly LOCAL_SCRIPTS_DIR="$SCRIPTS_DIR/local"
readonly ADMIRAL_ENV="$CONFIG_DIR/admiral.env"
readonly SSH_PRIVATE_KEY=$CONFIG_DIR/machinekey
readonly SSH_PUBLIC_KEY=$CONFIG_DIR/machinekey.pub
readonly MAX_DEFAULT_LOG_COUNT=6
readonly SSH_USER="root"
readonly LOCAL_BRIDGE_IP=172.17.42.1
readonly DOCKER_VERSION=1.13
readonly AWSCLI_VERSION=1.10.63
readonly API_TIMEOUT=600
export LC_ALL=C

# Installation default values #############################
###########################################################
export IS_UPGRADE=false
export NO_PROMPT=false
export KEYS_GENERATED=false
export OS_TYPE="Ubuntu_14.04"
export INSTALL_MODE="local"
###########################################################

source "$LIB_DIR/_logger.sh"
source "$LIB_DIR/_helpers.sh"
source "$LIB_DIR/_parseArgs.sh"

main() {
  __check_logsdir
  __parse_args "$@"
  __check_dependencies
  __validate_runtime
  __print_runtime

  source "$SCRIPTS_DIR/$OS_TYPE/installDb.sh"
  source "$SCRIPTS_DIR/create_sys_configs.sh"
  source "$SCRIPTS_DIR/create_vault_table.sh"
  source "$SCRIPTS_DIR/boot_admiral.sh"

  __process_msg "Installation successfully completed !!!"
}

main "$@"
