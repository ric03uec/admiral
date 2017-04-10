#!/bin/bash -e

# Helper methods ##########################################
###########################################################

__check_dependencies() {
  __process_marker "Checking dependencies"

  if type rsync &> /dev/null && true; then
    __process_msg "'rsync' already installed"
  else
    __process_msg "Installing 'rsync'"
    apt-get install -y rsync
  fi

  if type ssh &> /dev/null && true; then
    __process_msg "'ssh' already installed"
  else
    __process_msg "Installing 'ssh'"
    apt-get install -y ssh-client
  fi

  if type jq &> /dev/null && true; then
    __process_msg "'jq' already installed"
  else
    __process_msg "Installing 'jq'"
    apt-get install -y jq
  fi

  if type docker &> /dev/null && true; then
    __process_msg "'docker' already installed, checking version"
    local docker_version=$(docker --version)
    if [[ "$docker_version" == *"$DOCKER_VERSION"* ]]; then
      __process_msg "'docker' $DOCKER_VERSION installed"
    else
      __process_error "Docker version $docker_version installed, required $DOCKER_VERSION"
      __process_error "Install docker using script \"
      https://raw.githubusercontent.com/Shippable/node/master/scripts/ubu_14.04_docker_1.13.sh"
      exit 1
    fi
  else
    __process_msg "Docker not installed, installing Docker 1.13"
    rm -f installDockerScript.sh
    touch installDockerScript.sh
    echo '#!/bin/bash' >> installDockerScript.sh
    echo 'readonly MESSAGE_STORE_LOCATION="/tmp/cexec"' >> installDockerScript.sh
    echo 'readonly KEY_STORE_LOCATION="/tmp/ssh"' >> installDockerScript.sh
    echo 'readonly BUILD_LOCATION="/build"' >> installDockerScript.sh

    # Fetch the installation script and headers
    curl https://raw.githubusercontent.com/Shippable/node/$RELEASE/lib/logger.sh >> installDockerScript.sh
    curl https://raw.githubusercontent.com/Shippable/node/$RELEASE/lib/headers.sh >> installDockerScript.sh
    curl https://raw.githubusercontent.com/Shippable/node/$RELEASE/scripts/Ubuntu_14.04_Docker_1.13.sh >> installDockerScript.sh
    # Install Docker
    chmod +x installDockerScript.sh
    ./installDockerScript.sh
    rm installDockerScript.sh
  fi

  if type aws &> /dev/null && true; then
    __process_msg "'awscli' already installed"
  else
    __process_msg "Installing 'awscli'"
    apt-get -y install python-pip
    pip install awscli==$AWSCLI_VERSION
  fi

}

__print_runtime() {
  __process_marker "Installer runtime variables"
  __process_msg "RELEASE: $RELEASE"
  __process_msg "INSTALL_MODE: $INSTALL_MODE"
  __process_msg "IS_UPGRADE: $IS_UPGRADE"

  if [ $NO_PROMPT == true ]; then
    __process_msg "NO_PROMPT: true"
  else
    __process_msg "NO_PROMPT: false"
  fi
  __process_msg "ADMIRAL_IP: $ADMIRAL_IP"
  __process_msg "DB_IP: $DB_IP"
  __process_msg "DB_PORT: $DB_PORT"
  __process_msg "DB_USER: $DB_USER"
  __process_msg "DB_PASSWORD: $DB_PASSWORD"
  __process_msg "DB_NAME: $DB_NAME"
  __process_msg "Login Token: $LOGIN_TOKEN"
}

__generate_ssh_keys() {
  __process_msg "Generating SSH keys"
  local keygen_exec=$(ssh-keygen -t rsa -P "" -f $SSH_PRIVATE_KEY)
  __process_msg "SSH keys successfully generated"
}

__generate_login_token() {
  __process_msg "Generating login token"
  local uuid=$(cat /proc/sys/kernel/random/uuid)
  export LOGIN_TOKEN="$uuid"
  __process_msg "Successfully generated login token"
}

__set_admiral_ip() {
  __process_msg "Setting value of admiral IP address"
  local admiral_ip='127.0.0.1'

  __process_msg "Please enter your current IP address. This will be the address at which you access the installer webpage. Type D to set default (127.0.0.1) value."
  read response

  if [ "$response" != "D" ]; then
    __process_msg "Setting the admiral IP address to: $response, enter Y to confirm"
    read confirmation
    if [[ "$confirmation" =~ "Y" ]]; then
      admiral_ip=$response
    else
      __process_error "Invalid response, please enter a valid IP and confirm"
      __set_admiral_ip
    fi
  fi
  sed -i 's/.*ADMIRAL_IP=.*/ADMIRAL_IP="'$admiral_ip'"/g' $ADMIRAL_ENV
  __process_msg "Successfully set admiral IP to $admiral_ip"
}

__set_db_ip() {
  __process_msg "Setting value of database IP address"
  local db_ip="172.17.0.1"
  if [ "INSTALL_MODE" == "cluster" ]; then
    __process_msg "Please enter the IP address where you would like the database installed."
    read response

    if [ "$response" != "" ]; then
      __process_msg "Setting the database IP address to: $response, enter Y to confirm"
      read confirmation
      if [[ "$confirmation" =~ "Y" ]]; then
        db_ip=$response
      else
        __process_error "Invalid response, please enter a valid IP and continue"
        __set_db_ip
      fi
    fi
  fi

  sed -i 's/.*DB_IP=.*/DB_IP="'$db_ip'"/g' $ADMIRAL_ENV
  __process_msg "Successfully set DB_IP to $db_ip"
}

__set_db_password() {
  __process_msg "Setting database password"
  local db_password=""

  __process_msg "Please enter a password for your database."
  read response

  if [ "$response" != "" ]; then
    __process_msg "Setting the database password to: $response, enter Y to confirm"
    read confirmation
    if [[ "$confirmation" =~ "Y" ]]; then
      db_password=$response
    else
      __process_error "Invalid response, please enter a valid database password and continue"
      __set_db_password
    fi
  fi

  sed -i 's#.*DB_PASSWORD=.*#DB_PASSWORD="'$db_password'"#g' $ADMIRAL_ENV
  __process_msg "Successfully set database password"
}

__set_system_image_registry() {
  __process_msg "Setting system image registry"
  local system_image_registry=""

  __process_msg "Please enter the value of the Shippable system image registry."
  read response

  if [ "$response" != "" ]; then
    __process_msg "Setting the system image registry to: $response, enter Y to confirm"
    read confirmation
    if [[ "$confirmation" =~ "Y" ]]; then
      system_image_registry=$response
    else
      __process_error "Invalid response, please enter a valid system image registry and continue"
      __set_system_image_registry
    fi
  fi

  sed -i 's#.*SYSTEM_IMAGE_REGISTRY=.*#SYSTEM_IMAGE_REGISTRY="'$system_image_registry'"#g' $ADMIRAL_ENV
  __process_msg "Successfully set system image registry"
}

__copy_script_remote() {
  if [ "$#" -ne 3 ]; then
    __process_msg "The number of arguments expected by _copy_script_remote is 3"
    __process_msg "current arguments $@"
    exit 1
  fi

  local user="$SSH_USER"
  local key="$SSH_PRIVATE_KEY"
  local port=22
  local host="$1"
  shift
  local script_path_local="$1"
  local script_name=$(basename $script_path_local)
  shift
  local script_dir_remote="$1"
  local script_path_remote="$script_dir_remote/$script_name"

  remove_key_cmd="ssh-keygen -q -f '$HOME/.ssh/known_hosts' -R $host > /dev/null 2>&1"
  {
    eval $remove_key_cmd
  } || {
    true
  }

  __process_msg "Copying $script_path_local to remote host: $script_path_remote"
  _exec_remote_cmd $host "mkdir -p $script_dir_remote"
  copy_cmd="rsync -avz -e \
    'ssh \
      -o StrictHostKeyChecking=no \
      -o NumberOfPasswordPrompts=0 \
      -p $port \
      -i $SSH_PRIVATE_KEY \
      -C -c blowfish' \
      $script_path_local $user@$host:$script_path_remote"

  copy_cmd_out=$(eval $copy_cmd)
}

__copy_script_local() {
  local user="$SSH_USER"
  local key="$SSH_PRIVATE_KEY"
  local port=22
  local host="$1"
  shift
  local script_path_remote="$@"

  local script_dir_local="/tmp/shippable"

  echo "copying from $script_path_remote to localhost: /tmp/shippable/"
  remove_key_cmd="ssh-keygen -q -f '$HOME/.ssh/known_hosts' -R $host"
  {
    eval $remove_key_cmd
  } || {
    true
  }

  mkdir -p $script_dir_local
  copy_cmd="rsync -avz -e \
    'ssh \
      -o StrictHostKeyChecking=no \
      -o NumberOfPasswordPrompts=0 \
      -p $port \
      -i $SSH_PRIVATE_KEY \
      -C -c blowfish' \
      $user@$host:$script_path_remote $script_dir_local"

  copy_cmd_out=$(eval $copy_cmd)
  echo "$script_path_remote"
}

## syntax for calling this function
## __exec_remote_cmd "user" "192.156.6.4" "key" "ls -al"
__exec_remote_cmd() {
  local user="$SSH_USER"
  local key="$SSH_PRIVATE_KEY"
  local timeout=10
  local port=22

  local host="$1"
  shift
  local cmd="$@"

  local remote_cmd="ssh \
    -o StrictHostKeyChecking=no \
    -o NumberOfPasswordPrompts=0 \
    -o ConnectTimeout=$timeout \
    -p $port \
    -i $key \
    $user@$host \
    $cmd"

  {
    __process_msg "Executing on host: $host ==> '$cmd'" && eval "sudo -E $remote_cmd"
  } || {
    __process_msg "ERROR: Command failed on host: $host ==> '$cmd'"
    exit 1
  }
}

__exec_remote_cmd_proxyless() {
  local user="$SSH_USER"
  local key="$SSH_PRIVATE_KEY"
  local timeout=10
  local port=22

  local host="$1"
  shift
  local cmd="$@"
  shift

  local remote_cmd="ssh \
    -o StrictHostKeyChecking=no \
    -o NumberOfPasswordPrompts=0 \
    -o ConnectTimeout=$timeout \
    -p $port \
    -i $key \
    $user@$host \
    $cmd"

  {
    __process_msg "Executing on host: $host ==> '$cmd'" && eval "sudo $remote_cmd"
  } || {
    __process_msg "ERROR: Command failed on host: $host ==> '$cmd'"
    exit 1
  }
}
