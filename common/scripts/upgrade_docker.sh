#!/bin/bash -e

export INSTALL_DOCKER_SCRIPT="installDockerScript.sh"


__create_install_docker_script() {
  __process_msg "Creating docker install script"

  rm -f $INSTALL_DOCKER_SCRIPT
  touch $INSTALL_DOCKER_SCRIPT
  echo '#!/bin/bash' >> $INSTALL_DOCKER_SCRIPT
  echo 'install_docker_only="true"' >> $INSTALL_DOCKER_SCRIPT
  echo "SHIPPABLE_HTTP_PROXY=\"$SHIPPABLE_HTTP_PROXY\"" >> installDockerScript.sh
  echo "SHIPPABLE_HTTPS_PROXY=\"$SHIPPABLE_HTTPS_PROXY\"" >> installDockerScript.sh
  echo "SHIPPABLE_NO_PROXY=\"$SHIPPABLE_NO_PROXY\"" >> installDockerScript.sh

  local node_scripts_location=/tmp/node
  local node_s3_location="https://s3.amazonaws.com/shippable-artifacts/node/$RELEASE/node-$RELEASE.tar.gz"

  pushd /tmp
  mkdir -p $node_scripts_location
  wget $node_s3_location
  tar -xzf node-$RELEASE.tar.gz -C $node_scripts_location --strip-components=1
  rm -rf node-$RELEASE.tar.gz
  popd

  cat $node_scripts_location/lib/logger.sh >> $INSTALL_DOCKER_SCRIPT
  cat $node_scripts_location/lib/headers.sh >> $INSTALL_DOCKER_SCRIPT
  cat $node_scripts_location/initScripts/$ARCHITECTURE/$OPERATING_SYSTEM/Docker_"$DOCKER_VERSION".sh >> $INSTALL_DOCKER_SCRIPT

  rm -rf $node_scripts_location
  # Install Docker
  chmod +x $INSTALL_DOCKER_SCRIPT
}

__remove_services() {
  __process_msg "Removing all the services"

  local current_services=$(sudo docker service ls -q)
  if [ ! -z "$current_services" ]; then
    sudo docker service rm $current_services || true
  fi
}

__update_docker_on_swarm_workers() {
  __process_msg "Upgrading docker version on swarm workers"
  ## Note: this always needs to execute since it'll update proxy settings on
  ## swarm worker nodes

  local system_settings="PGPASSWORD=$DB_PASSWORD \
    psql \
    -U $DB_USER \
    -d $DB_NAME \
    -h $DB_IP \
    -p $DB_PORT \
    -v ON_ERROR_STOP=1 \
    -tc 'SELECT workers from \"systemSettings\"; '"

  {
    system_settings=`eval $system_settings` &&
    __process_msg "'systemSettings' table exists, finding workers"
  } || {
    __process_msg "'systemSettings' table does not exist, skipping"
    return
  }

  local workers=$(echo $system_settings | jq '.')
  local workers_count=$(echo $workers | jq '. | length')

  local get_master_cmd="PGPASSWORD=$DB_PASSWORD \
    psql \
    -U $DB_USER \
    -d $DB_NAME \
    -h $DB_IP \
    -p $DB_PORT \
    -v ON_ERROR_STOP=1 \
    -tc 'SELECT master from \"systemSettings\"; '"
  local master=$(eval $get_master_cmd | jq '.');
  local master_address=$(echo $master | jq '.address');

  __process_msg "Found $workers_count workers"
  for i in $(seq 1 $workers_count); do
    local worker=$(echo $workers | jq '.['"$i-1"']')
    local host=$(echo $worker | jq -r '.address')
    local port=$(echo $worker | jq -r '.port')
    local is_initialized=$(echo $worker | jq -r '.isInitialized')
    if [ $is_initialized == false ]; then
      __process_msg "worker $host not initialized, skipping"
      continue
    fi

    if [ $host == $ADMIRAL_IP ]; then
      continue
    fi

    local script_name="installWorker.sh"
    local install_worker_script="$SCRIPTS_DIR/$ARCHITECTURE/$OPERATING_SYSTEM/remote/$script_name"
    local worker_install_cmd="WORKER_HOST=$host \
      WORKER_JOIN_TOKEN=$SWARM_WORKER_JOIN_TOKEN \
      WORKER_PORT=$port \
      MASTER_HOST=$master_address \
      RELEASE=$RELEASE \
      NO_VERIFY_SSL=$NO_VERIFY_SSL \
      ARCHITECTURE=$ARCHITECTURE \
      OPERATING_SYSTEM=$OPERATING_SYSTEM \
      INSTALLED_DOCKER_VERSION=$DOCKER_VERSION \
      SHIPPABLE_HTTP_PROXY=$SHIPPABLE_HTTP_PROXY \
      SHIPPABLE_HTTPS_PROXY=$SHIPPABLE_HTTPS_PROXY \
      SHIPPABLE_NO_PROXY=$SHIPPABLE_NO_PROXY \
      $SCRIPTS_DIR_REMOTE/$script_name"

    __copy_script_remote "$host" "$install_worker_script" "$SCRIPTS_DIR_REMOTE"
    __exec_cmd_remote "$host" "$worker_install_cmd"
  done
}

__update_docker() {
  ## Note: this always needs to execute since it'll update proxy settings on
  ## swarm master

  __process_msg "Upgrading docker to $DOCKER_VERSION"
  __create_install_docker_script
  ./$INSTALL_DOCKER_SCRIPT
  rm -f $INSTALL_DOCKER_SCRIPT
}

__upgrade_awscli_version() {
  __process_msg "Upgrading AWS cli to : $AWSCLI_VERSION"
  pip install awscli==$AWSCLI_VERSION
}

__restart_db_container() {
  local db_container_name="db"
  local db_container=$(sudo docker ps -a --format "{{.Names}}" | grep -w "db") || true
  if [ ! -z "$db_container" ]; then
    __process_msg "Found a stopped $db_container_name container, starting it"
    sudo docker start "$db_container_name"
    sleep 3
  else
    __process_msg "DB not running as a container"
  fi
}

__restart_admiral() {
  __process_msg "Booting admiral container"
  source $SCRIPTS_DIR/$ARCHITECTURE/$OPERATING_SYSTEM/boot_admiral.sh
  sleep 5
}

__restart() {
  IS_RESTART=true
  export skip_starting_services=true
  source $SCRIPTS_DIR/restart.sh
  IS_RESTART=false
}

main() {
  __process_marker "Upgrading docker"
  __remove_services
  __update_docker
  __update_docker_on_swarm_workers
  __upgrade_awscli_version
  __set_installed_docker_version
  __restart_db_container
  __restart_admiral
  __restart

  rm -f "$INSTALL_DOCKER_SCRIPT"
}

main
