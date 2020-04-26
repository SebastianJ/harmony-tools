#!/bin/bash

# Harmony double-signing setup
version="0.0.1"
script_name="report.sh"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --path               path            where to export reports
   --address            address         the address to the pprof server
   --cpu-interval       seconds         how long pprof should profile the cpu (defaults to 60 seconds)
   --interval           interval        how often to export reports
   --help                               print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --path) path="${2%/}" ; shift;;
  --address) address="$2" ; shift;;
  --cpu-interval) cpu_interval="$2" ; shift;;
  --interval) interval="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_vars() {
  if [ -z "$path" ]; then
    path="pprof"
  fi

  if [ -z "$address" ]; then
    address="localhost:6070"
  fi

  if [ -z "$cpu_interval" ]; then
    cpu_interval=60
  fi

  if [ -z "$interval" ]; then
    interval="5m"
  fi

  packages=(curl tmux graphviz)
}

detect_distro() {
    if command -v apt-get >/dev/null 2>&1; then
      distro="debian"
    fi

    if command -v yum >/dev/null 2>&1; then
      distro="rhel"
    fi
}

check_dependencies() {
  if ! command -v go >/dev/null 2>&1; then
    echo "You need to have go installed on your system! Please install it"
    exit 1
  fi

  local missing_packages=()
  for package in "${packages[@]}"; do
    case $distro in
    debian)
      if ! dpkg-query -W $package >/dev/null 2>&1; then
        missing_packages+=($package)
      fi
      ;;
    rhel)
      if ! rpm -q $package >/dev/null 2>&1; then
        missing_packages+=($package)
      fi
      ;;
    *)
      ;;
    esac
  done

  if (( ${#missing_packages[@]} )); then
    need_to_install=${missing_packages[@]}
    echo "The following packages need to be installed: ${need_to_install}"
    echo "Please install them using:"

    case $distro in
    debian)
      echo "sudo apt-get install -y ${need_to_install}"
      ;;
    rhel)
      echo "sudo yum install ${need_to_install}"
      ;;
    *)
      ;;
    esac
    
    exit 1
  fi
}

initialize() {
  set_vars
  detect_distro
  check_dependencies
}

report() {
  timestamp=$(date -u "+%Y-%m-%d-%H-%M-%S-%Z")
  report_path="${path}/${timestamp}"
  mkdir -p $report_path
  echo "Generating memory allocs report"
  go tool pprof --pdf http://$address/debug/pprof/allocs > $report_path/memory-allocs.pdf

  echo "Generating memory heap report"
  go tool pprof --pdf http://$address/debug/pprof/heap > $report_path/memory-heap.pdf

  echo "Generating cpu profile report"
  go tool pprof --pdf http://$address/debug/pprof/profile?seconds=$cpu_interval > $report_path/cpu-profile.pdf

  echo "Waiting ${interval} before generating the next set of reports..."
}

initialize

while true; do
  report
  if [ ! $? -eq 0 ]; then
    break
  fi
  sleep $interval
done
