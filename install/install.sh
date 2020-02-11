#!/bin/bash

# Harmony custom install script - installs binaries from a custom S3 repo
version="0.0.1"
script_name="install.sh"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --node                   if a new node.sh file should be downloaded from harmony-one/harmony (master)
   --node-sh-url    path    where to download node.sh from (defaults to https://raw.githubusercontent.com/harmony-one/harmony/master/scripts/node.sh)
   --binaries-url   path    where to download the binaries from (defaults to http://tools.harmony.one.s3.amazonaws.com/release/linux-x86_64/harmony)
   --bootnode               if the bootnode binary should be downloaded
   --help                   print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --node) should_download_node_sh=true ;;
  --node-sh-url) node_sh_url="$2" ; shift;;
  --binaries-url) binaries_url="$2" ; shift;;
  --bootnode) should_download_bootnode=true ;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

initialize() {
  if [ -z "$should_download_node_sh" ]; then
    should_download_node_sh=false
  fi

  if [ -z "$should_download_bootnode" ]; then
    should_download_bootnode=false
  fi

  if [ -z "$node_sh_url" ]; then
    node_sh_url="https://raw.githubusercontent.com/harmony-one/harmony/master/scripts/node.sh"
  fi

  if [ -z "$binaries_url" ]; then
    binaries_url="http://tools.harmony.one.s3.amazonaws.com/release/linux-x86_64/harmony"
  fi

  binaries=(harmony hmy)

  if [ "$should_download_bootnode" = true ]; then
    binaries+=(bootnode)
  fi
}

download_binaries() {
  for binary in "${binaries[@]}"; do
    echo "Downloading ${binary} from ${binaries_url}/${binary} ..."
    rm -rf ${binary} && wget ${binaries_url}/${binary} && chmod u+x ${binary}
  done
}

download_node_sh() {
  if [ "$should_download_node_sh" = true ]; then
    echo ""
    echo "Downloading the latest node.sh from harmony-one/harmony (master) ..."
    rm -rf node.sh && wget ${node_sh_url} && chmod u+x node.sh
  fi
}

install() {
  initialize
  download_binaries
  download_node_sh

  echo "Everything has now been downloaded."
  echo ""
  echo "Make sure to start your node using -D to not overwrite your custom binaries!"
  echo ""

  if [ "$should_download_node_sh" = true ]; then
    echo "Node.sh version:"
    ./node.sh -v
    echo ""
  fi

  echo "Harmony binary version:"
  ./node.sh -V
  
  echo ""
}

install
