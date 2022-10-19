#!/usr/bin/env bash
INSPECTIT_ROOT_FOLDER=$(dirname $(dirname $(readlink -f $0)))
DEMO_SETUP_FOLDER="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
BUILD_FOLDER="${DEMO_SETUP_FOLDER}/build"


function delete_build_dir() {
    rm -rf "${BUILD_FOLDER}"
}

function create_build_dir(){
  delete_build_dir
  mkdir "${BUILD_FOLDER}"
}


function build_config_server(){
  version=$1
  if [ -z "$version" ]; then version="SNAPSHOT"; fi
  create_build_dir
  echo "Build config server amd64 image"
  cd "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot" || exit
  ./gradlew inspectit-ocelot-configurationserver:assemble bootJarWithFrontend

  cp -R "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot/components/inspectit-ocelot-configurationserver/docker" "${BUILD_FOLDER}/config-server-docker"
  cp "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot/components/inspectit-ocelot-configurationserver/build/libs/inspectit-ocelot-configurationserver-SNAPSHOT.jar" "${BUILD_FOLDER}/config-server-docker/inspectit-ocelot-configurationserver.jar"
  docker buildx   build --load --platform linux/arm64  -t inspectit/inspectit-ocelot-configurationserver:$version "${BUILD_FOLDER}/config-server-docker/"
  delete_build_dir
}

function build_eum_server(){
  create_build_dir
  echo "Build eum server amd64 image"
  cd "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot-eum-server" || exit
  ./gradlew build
  cp -R "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot-eum-server/docker" "${BUILD_FOLDER}/eum-server-docker"
  cp "${INSPECTIT_ROOT_FOLDER}/inspectit-ocelot-eum-server/build/libs/inspectit-ocelot-eum-server-SNAPSHOT.jar" "${BUILD_FOLDER}/eum-server-docker/inspectit-ocelot-eum-server.jar"
  docker buildx build --load --platform linux/arm64  -t inspectit/inspectit-ocelot-eum-server:SNAPSHOT "${BUILD_FOLDER}/eum-server-docker/"
  delete_build_dir
}


function build_trading_demo_app(){
  echo "Build Trading Demo App"
  cd "${INSPECTIT_ROOT_FOLDER}/trading-demo-application" || exit
  ./gradlew bootJar
  docker buildx build --load --platform linux/arm64  -t inspectit/trading-demo-app:SNAPSHOT .
}


usage()
{
cat << EOF
Generate CA APM Agents.
Generation requires a perl installation.

OPTIONS:
   -h               Show this message
   -c               Build Ocelot Configuration Server
   -e               Build Ocelot EUM Server
   -t               Build Trading Demo App
EOF
}

while getopts "hc:e:t:" opt; do
  case $opt in
    h)
      usage
      exit 1
      ;;
    c)
    # invoke self with all arguments
     build_config_server "$OPTARG"
      ;;
    e)
    # invoke self with all arguments
     build_eum_server "$OPTARG"
      ;;
    t)
    # invoke self with all arguments
     build_trading_demo_app "$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

