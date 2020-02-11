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
   --node       if a new node.sh file should be downloaded from harmony-one/harmony (master)
   --s3-url     what s3 base url to use for uploading binaries (defaults to s3://tools.harmony.one/release/linux-x86_64/harmony)
   --help       print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --node) should_download_node_sh=true ;;
  --s3-url) s3_url="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

initialize() {
  binaries=(harmony bootnode wallet hmy)

  if [ -z "$should_download_node_sh" ]; then
    should_download_node_sh=false
  fi

  if [ -z "$s3_url" ]; then
    s3_url="s3://tools.harmony.one/release/linux-x86_64/harmony"
  fi
}

download_binaries() {
  for binary in "${binaries[@]}"; do
    echo "Downloading ${binary} from ${s3_url}/${binary} ..."
    rm -rf ${binary} && wget ${s3_url}/${binary} && chmod u+x ${binary}
  done
}

download_node_sh() {
  echo ""
  echo "Downloading the latest node.sh from harmony-one/harmony (master) ..."
  rm -rf node.sh && wget https://raw.githubusercontent.com/harmony-one/harmony/master/scripts/node.sh && chmod u+x node.sh
}

install() {
  initialize
  download_binaries

  if [ "$should_download_node_sh" = true ]; then
    download_node_sh
  fi

  echo "Everything has now been downloaded."
  echo ""
  echo "Make sure to start your node using -D to not overwrite your custom binaries!"
  echo ""
}

install
