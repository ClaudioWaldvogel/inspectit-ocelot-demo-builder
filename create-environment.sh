#!/bin/bash
trap error_handler ERR;
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

function error_handler() {
   printf "${RED}Environment creation failed. Check logs. Aborting...${NC}";
   exit 1;
}

docker_compose_file_name=docker-compose.yaml
components_directory=components
force_environment_creation=false
environment_root_directory=envs
config_file_name=
environment_name=
environment_directory=
docker_compose_file=



usage()
{
cat << EOF
This scripts creates a inspectit environment

OPTIONS:
   -h   Show this message
   -c   The config file for the environment
   -d   The directory where to store the environment. Defaults to envs
   -f   Force environment creation. Override existing if present.
EOF
}



while getopts "hfd:c:" opt; do
  case $opt in
    h)
      usage
      exit 1
      ;;
    c)
      config_file_name=$OPTARG
      if [ ! -f "$config_file_name" ]; then
          printf "${RED}%s does not exist.${NC}\n" "$config_file_name";
          exit 1
      fi
      ;;
    f)
      force_environment_creation=true
      ;;
    d)
     environment_root_directory=$OPTARG
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

function attach_traefik(){
TRAEFIK_VERSION=$(jq -r '.traefik.version' "$config_file_name")
TRAEFIK_DASHBOARD_PORT=$(jq -r '.traefik.dashboard_port' "$config_file_name")
TRAEFIK_WEB_PORT=$(jq -r '.traefik.web_port' "$config_file_name")
cp -r "${components_directory}/traefik" "$environment_directory/"
/bin/cat <<EOM >>"${docker_compose_file}"
  traefik:
    image: "traefik:${TRAEFIK_VERSION}"
    container_name: "${environment_domain_prefix}-traefik"
    networks:
      - "$docker_network_name"
    command:
      - "--api.insecure=true"
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--tracing.jaeger.propagation=b3"
    ports:
      - "${TRAEFIK_WEB_PORT}:80"
      - "${TRAEFIK_DASHBOARD_PORT}:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-traefik.rule=Host(\`${environment_domain_prefix}.traefik.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-traefik.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-traefik.service=${environment_domain_prefix}-traefik"
      - "traefik.http.services.${environment_domain_prefix}-traefik.loadbalancer.server.port=8080"
EOM
}

function attach_config_server(){
  cfg_srv_enabled=$(jq -r '.config_server.enabled' "$config_file_name")
  if [ "$cfg_srv_enabled" = true ] ; then
      cp -r "${components_directory}/config-server" "$environment_directory/"
      build_arm_image=$(jq -r '.config_server.build_arm_image' "$config_file_name")
      version=$(jq -r '.config_server.version' "$config_file_name")
      if [ "$build_arm_image" = true ] ; then
        /bin/bash build-arm-docker-images.sh -c "$version"
      fi
      /bin/cat <<EOM >>"${docker_compose_file}"

  ocelot-config-server:
    image: inspectit/inspectit-ocelot-configurationserver:${version}
    container_name: "${environment_domain_prefix}-ocelot-config-server"
    networks:
      - "$docker_network_name"
    environment:
      - INSPECTIT_CONFIG_SERVER_WORKING_DIRECTORY=/config-server
      - INSPECTIT_CONFIG_SERVER_DEFAULT_USER_PASSWORD=demo
      - INSPECTIT_CONFIG_HTTP_URL=http://ocelot-config-server:8090/api/v1/agent/configuration
      - INSPECTIT_SERVICE_NAME="Config Server"
    volumes:
      - ./config-server:/config-server
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-config-srv.rule=Host(\`${environment_domain_prefix}.config-srv.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-config-srv.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-config-srv.service=${environment_domain_prefix}-configuration-server"
      - "traefik.http.services.${environment_domain_prefix}-configuration-server.loadbalancer.server.port=8090"
EOM
  fi

}

function attach_eum_server(){
  cfg_srv_enabled=$(jq -r '.eum_server.enabled' "$config_file_name")
  if [ "$cfg_srv_enabled" = true ] ; then
      build_arm_image=$(jq -r '.eum_server.build_arm_image' "$config_file_name")
      version=$(jq -r '.eum_server.version' "$config_file_name")
      if [ "$build_arm_image" = true ] ; then
        /bin/bash build-arm-docker-images.sh -e "$version"
      fi
      /bin/cat <<EOM >>"${docker_compose_file}"

  ocelot-eum-server:
    image: inspectit/inspectit-ocelot-eum-server:${version}
    container_name: "${environment_domain_prefix}-ocelot-eum-server"
    networks:
      - "$docker_network_name"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-eum-srv.rule=Host(\`${environment_domain_prefix}.eum-srv.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-eum-srv.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-eum-srv.service=${environment_domain_prefix}-eum-server"
      - "traefik.http.services.${environment_domain_prefix}-eum-server.loadbalancer.server.port=8085"

EOM
  fi

}

function attach_prometheus(){
  cfg_srv_enabled=$(jq -r '.prometheus.enabled' "$config_file_name")
  if [ "$cfg_srv_enabled" = true ] ; then
       cp -r "${components_directory}/prometheus" "$environment_directory/"
      version=$(jq -r '.prometheus.version' "$config_file_name")

/bin/cat <<EOM >>"${docker_compose_file}"

  prometheus:
    image: prom/prometheus:${version}
    container_name: "${environment_domain_prefix}-prometheus"
    networks:
      - "$docker_network_name"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - 9090
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-prometheus.rule=Host(\`${environment_domain_prefix}.prometheus.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-prometheus.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-prometheus.service=${environment_domain_prefix}-prometheus"
      - "traefik.http.services.${environment_domain_prefix}-prometheus.loadbalancer.server.port=9090"

EOM
  fi
}

function attach_influx(){
  influx_enabled=$(jq -r '.influx.enabled' "$config_file_name")
    if [ "$influx_enabled" = true ] ; then
        cp -r "${components_directory}/influx" "$environment_directory/"
        version=$(jq -r '.influx.version' "$config_file_name")

/bin/cat <<EOM >>"${docker_compose_file}"
  influxdb:
    image: influxdb:${version}
    container_name: "${environment_domain_prefix}-influxdb"
    networks:
      - "$docker_network_name"
    environment:
      - INFLUXDB_HTTP_FLUX_ENABLED=true
      - INFLUXDB_HTTP_LOG_ENABLED=false
      - INFLUXDB_DATA_QUERY_LOG_ENABLED=false
    volumes:
      - ./influx:/docker-entrypoint-initdb.d
    ports:
      - "8086"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-influx.rule=Host(\`${environment_domain_prefix}.influxdb.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-influx.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-influx.service=${environment_domain_prefix}-influx"
      - "traefik.http.services.${environment_domain_prefix}-influx.loadbalancer.server.port=8086"
EOM


    fi
}

function attach_jaeger(){
  cfg_srv_enabled=$(jq -r '.jaeger.enabled' "$config_file_name")
  if [ "$cfg_srv_enabled" = true ] ; then
      version=$(jq -r '.jaeger.version' "$config_file_name")

/bin/cat <<EOM >>"${docker_compose_file}"

  jaeger:
    image: "jaegertracing/all-in-one:${version}"
    container_name: "${environment_domain_prefix}-jaeger"
    networks:
      - "$docker_network_name"
    ports:
     #- "6831:6831/udp"
     #- "6832:6832/udp"
     #- "5778:5778"
     #- "16686:16686"
     #- "14268:14268"
     #- "9411:9411"
     - "6832/udp"
     - "5778"
     - "16686"
     - "14268"
     - "9411"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-jaeger.rule=Host(\`${environment_domain_prefix}.jaeger-ui.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-jaeger.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-jaeger.service=${environment_domain_prefix}-jaeger-ui"
      - "traefik.http.services.${environment_domain_prefix}-jaeger-ui.loadbalancer.server.port=16686"

      - "traefik.http.routers.${environment_domain_prefix}-jaeger-traces.rule=Host(\`${environment_domain_prefix}.jaeger-traces.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-jaeger-traces.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-jaeger-traces.service=${environment_domain_prefix}-jaeger-traces"
      - "traefik.http.services.${environment_domain_prefix}-jaeger-traces.loadbalancer.server.port=14268"

EOM
  fi

}


function attach_trading_app(){

  cfg_srv_enabled=$(jq -r '.trading_app.enabled' "$config_file_name")
  if [ "$cfg_srv_enabled" = true ] ; then
      build_arm_image=$(jq -r '.trading_app.build_arm_image' "$config_file_name")
      version=$(jq -r '.trading_app.version' "$config_file_name")
      cp -r "${components_directory}/trading-demo-load" "$environment_directory/"
      if [ "$build_arm_image" = true ] ; then
        /bin/bash build-arm-docker-images.sh -t "$version"
      fi

/bin/cat <<EOM >>"${docker_compose_file}"

  trading-app-frontend:
    image: inspectit/trading-demo:${version}
    container_name: "${environment_domain_prefix}-trading-app-frontend"
    networks:
      - "$docker_network_name"
    environment:
      # We can not use e.g http://trading-backend.test since we do not have dnsmasq installed in the container
      - BACKEND_URL=http://trading-app-backend:8080
      - INSPECTIT_CONFIG_HTTP_URL=http://ocelot-config-server:8090/api/v1/agent/configuration
      - "INSPECTIT_SERVICE_NAME=Trading Frontend"
    volumes:
      - "${agent_location}:/agent/agent.jar"
    entrypoint: [ "java","-javaagent:/agent/agent.jar", "-jar","/trading-demo.jar" ]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-trading-frontend.rule=Host(\`${environment_domain_prefix}.trading-frontend.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-trading-frontend.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-trading-frontend.service=${environment_domain_prefix}-trading-frontend"
      - "traefik.http.services.${environment_domain_prefix}-trading-frontend.loadbalancer.server.port=8080"


  trading-app-backend:
    image: inspectit/trading-demo:${version}
    container_name: "${environment_domain_prefix}-trading-app-backend"
    networks:
      - "$docker_network_name"
    environment:
      - INSPECTIT_CONFIG_HTTP_URL=http://ocelot-config-server:8090/api/v1/agent/configuration
      - "INSPECTIT_SERVICE_NAME=Trading Backend"
    volumes:
      - "${agent_location}:/agent/agent.jar"
    entrypoint: [ "java","-javaagent:/agent/agent.jar", "-jar","/trading-demo.jar" ]


  trading-app-load:
    container_name: "${environment_domain_prefix}-trading-app-load"
    image: curlimages/curl:7.85.0
    networks:
      - "$docker_network_name"
    volumes:
      - ./trading-demo-load/load.sh:/opt/load.sh
    entrypoint: /opt/load.sh

EOM
  fi

}


function attach_otel_collector() {

  otel_collector_enabled=$(jq -r '.otel_collector.enabled' "$config_file_name")
  if [ "$otel_collector_enabled" = true ] ; then
      version=$(jq -r '.otel_collector.version' "$config_file_name")
      cp -r "${components_directory}/otel-collector" "$environment_directory/"

/bin/cat <<EOM >>"${docker_compose_file}"

  otel-collector:
    image: otel/opentelemetry-collector:${version}
    container_name: "${environment_domain_prefix}-otel-collector"
    command: ["--config=/etc/otel-collector-config.yaml"]
    networks:
      - "$docker_network_name"
    volumes:
      - ./otel-collector/otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "1888:1888"   # pprof extension
      - "8888:8888"   # Prometheus metrics exposed by the collector
      - "8889:8889"   # Prometheus exporter metrics
      - "13133:13133" # health_check extension
      - "4317:4317"   # OTLP gRPC receiver
      - "4318:4318"   # OTLP http receiver
      - "55679:55679" # zpages extension
EOM
  fi
}

function attach_telegraf() {

  telegraf_enabled=$(jq -r '.telegraf.enabled' "$config_file_name")
  if [ "$telegraf_enabled" = true ] ; then
      version=$(jq -r '.telegraf.version' "$config_file_name")
      cp -r "${components_directory}/telegraf" "$environment_directory/"

/bin/cat <<EOM >>"${docker_compose_file}"

  telegraf:
    image: telegraf:1.24.2
    container_name: "${environment_domain_prefix}-telegraf"
    networks:
      - "$docker_network_name"
    volumes:
      - ./telegraf/telegraf.conf:/etc/telegraf/telegraf.conf
    ports:
      - "43177:4317"   # OTLP gRPC receiver
      - "8125:8125"   # StatsD
      - "8092:8092"   # UDP
      - "8094:8094"   # TCP
EOM
  fi
}

function attach_grafana() {

  grafana_enabled=$(jq -r '.grafana.enabled' "$config_file_name")
  if [ "$grafana_enabled" = true ] ; then
      version=$(jq -r '.grafana.version' "$config_file_name")
      cp -r "${components_directory}/grafana" "$environment_directory/"
      provisioner=prometheus
      influx_enabled=$(jq -r '.influx.enabled' "$config_file_name")
      if [ "$influx_enabled" = true ] ; then
        provisioner=influxdb
      fi


/bin/cat <<EOM >>"${docker_compose_file}"

  grafana:
    image: grafana/grafana:${version}
    container_name: "${environment_domain_prefix}-grafana"
    networks:
      - "$docker_network_name"
    environment:
      - GF_PANELS_DISABLE_SANITIZE_HTML=TRUE
      - GF_AUTH_BASIC_ENABLED=false
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
      - GF_PATHS_PROVISIONING=/usr/share/grafana/custom/
      - GF_INSTALL_PLUGINS=https://github.com/NovatecConsulting/novatec-service-dependency-graph-panel/releases/download/v4.0.2/novatec-sdg-panel.zip;novatec-sdg-panel
    volumes:
      - ./grafana/provisioning/${provisioner}:/usr/share/grafana/custom/
      - ./grafana/provisioning/home-dashboard/home.json:/usr/share/grafana/public/dashboards/home.json
    ports:
      - 3000
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${environment_domain_prefix}-grafana.rule=Host(\`${environment_domain_prefix}.grafana.${environment_domain_postfix}\`)"
      - "traefik.http.routers.${environment_domain_prefix}-grafana.entrypoints=web"
      - "traefik.http.routers.${environment_domain_prefix}-grafana.service=${environment_domain_prefix}-grafana"
      - "traefik.http.services.${environment_domain_prefix}-grafana.loadbalancer.server.port=3000"
EOM
  fi
}

function start_compose_file(){
# Begin compose file and set all service which are always added
/bin/cat <<EOM >>"${docker_compose_file}"
version: '3.3'
networks:
  "$docker_network_name":
    driver: bridge
services:
EOM
}


function build_environment() {

  environment_name=$(jq -r '.name' "$config_file_name")
  environment_domain_prefix=$(jq -r '.domain_prefix' "$config_file_name")
  environment_domain_postfix=$(jq -r '.domain_postfix' "$config_file_name")

  config_dir=$(dirname "$(realpath -s "$config_file_name")")
  agent_location=$(realpath "${config_dir}/$(jq -r '.agent_location' "$config_file_name")")

  environment_directory="$environment_root_directory/$environment_name"
  # Ensure environment directory exists
  if [ ! -d "$environment_directory" ]; then
      printf "Create environment_directory <%s>\n" "$environment_directory";
      mkdir -p "$environment_directory"
  else
      if [ "$force_environment_creation" != true ] ; then
      printf "${RED}Environment <%s> already exists. Do you want to override existing environment?${NC}\n" "$environment_directory";
          select yn in "Yes" "No"; do
                  case $yn in
                      Yes ) echo "Overriding environment $environment_directory"; break;;
                      No ) echo "Aborting"; exit;;
                  esac
              done
      else
        echo "Overriding environment $environment_directory"
      fi
  fi


  docker_compose_file="${environment_directory}/${docker_compose_file_name}"
  docker_network_name="$environment_domain_prefix-$environment_name"
  if [ -f "$docker_compose_file" ]; then
       rm "$docker_compose_file"
  fi



  start_compose_file
  attach_traefik
  attach_config_server
  attach_eum_server
  attach_prometheus
  attach_influx
  attach_jaeger
  attach_trading_app
  attach_grafana
  attach_otel_collector
  attach_telegraf

}

build_environment  "$config_file_name"