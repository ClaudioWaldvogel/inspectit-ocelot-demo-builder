# Utility tool to create inspectIT dev environments
 
Based on a json configuration it is possible to create a docker-compose.yml including a set of infrastructure components to ease inspectit development.  
The following components are supported:
- inspectIT Configuration Server (http://\<environment-name\>.config-srv.test) (admin/demo)
- inspectIT EUM Server (http://\<environment-name\>.eum-srv.test)
- Grafana  (http://\<environment-name\>.grafana.test)
- Jaeger (http://\<environment-name\>.jaeger.test)
- InfluxDB (http://\<environment-name\>.influxdb.test)
- Prometheus (http://\<environment-name\>.prometheus.test)
- Trading demo application (http://\<environment-name\>.trading-frontend.test)

Sample configurations are available at _\<project-dir\>/example-configurations._

To bypass the burden of knowing all ports of the different components all components are proxied through traefik revers proxy.

To enabled proper DNS resolution it is required to install dnsmasq and setup a resolver. See 


## Known limitations
- Currently only tested on MACOS
- Path names must not contain blanks

## Prerequisites 
- Ensure realpath bash function is available
  ````bash
  # MacOS installation with brew
  brew install coreutils
  ````
- Install dnsmasq and perform the steps described [here](https://gist.github.com/ogrrd/5831371)
    ```bash
  # MacOS installation with brew
  brew install dnsmasq
    ```

### Build ARM Images for Apple Silicon Chip
At time of writing inspectIT does not ship multi arch images for configuration-server, eum-server and trading-demo-application.  
It is possible to enable the build flag for those components in a configuration file.
To enable arm images build sources of the components must be available on the same hierarch level as the demo builder.

#### Config server
- Yarn must be installed
- NPM must be installed
- if build fails turn of downloading npm version in build.gradle of inspectit-ocelot-configurationserver package
- Node version > 16


## Creating environments
```bash
# Create environment for config in dev-environments directory
./create-environment.sh -c ../dev-environments/demo1.json -d ../dev-environments
# Start environment
cd ../dev-environments/demo1
docker-compose up -d
```
Now you can e.ge access configuration-server with your Browser at: http://demo1.config-srv.test.

--- 
### Sample configuration
```json
{
  "name": "demo1",
  "domain_prefix": "demo1",
  "domain_postfix": "test",
  "agent_location": "<path>/inspectit-ocelot-agent-SNAPSHOT.jar",
  "traefik": {
    "version": "2.8",
    "dashboard_port": 8088,
    "web_port": 80
  },
  "config_server": {
    "enabled": true,
    "build_arm_image": false,
    "version": "2.1.1"
  },
  "eum_server": {
    "enabled": true,
    "build_arm_image": false,
    "version": "2.0.0"
  },
  "prometheus": {
    "enabled": false,
    "version": "v2.36.2"
  },
  "influx": {
    "enabled": true,
    "version": "1.8.10"
  },
  "jaeger": {
    "enabled": true,
    "version": 1.35
  },
  "grafana": {
    "enabled": true,
    "version": "9.1.8"
  },
  "trading_app": {
    "enabled": true,
    "version": "latest",
    "build_arm_image": false
  }
}
```

---
### Excerpt from  https://gist.github.com/ogrrd/5831371

## Requirements

* [Homebrew](https://brew.sh/)
* Mountain Lion -> High Sierra

## Install
```
brew install dnsmasq
```

## Setup

### Create config directory
```
mkdir -pv $(brew --prefix)/etc/
```

### Setup *.test

```
echo 'address=/.test/127.0.0.1' >> $(brew --prefix)/etc/dnsmasq.conf
```
### Change port for High Sierra
```
echo 'port=53' >> $(brew --prefix)/etc/dnsmasq.conf
```

## Autostart - now and after reboot
```
sudo brew services start dnsmasq
```

## Add to resolvers

### Create resolver directory
```
sudo mkdir -v /etc/resolver
```

### Add your nameserver to resolvers
```
sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/test'
```

## Finished

That's it! You can run scutil --dns to show all of your current resolvers, and you should see that all requests for a domain ending in .test will go to the DNS server at 127.0.0.1

## N.B. never use .dev as a TLD for local dev work. .test is fine though.