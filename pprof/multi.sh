#!/bin/bash

# Author: Sebastian Johnsson - https://github.com/SebastianJ

version="0.0.1"
script_name="multi.sh"

#
# Arguments/configuration
# 
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --hosts  hosts   a comma separated/delimited list of hosts you want to output reports for
   --file   path    path to file containing hosts to output reports for
   --help           print this help
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --hosts) hosts_string="${2}" ; shift;;
  --file) file_path="${2}" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_vars() {
  default_port=6060
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

cleanup_pprof() {
  rm -rf ~/pprof
}

initialize() {
  set_vars
  cleanup_pprof
  detect_distro
  check_dependencies
}

parse_hosts() {
  if [ -z "$hosts_string" ]; then
    if [ ! -z "$file_path" ] && test -f $file_path; then
      IFS=$'\n' read -d '' -r -a hosts < $file_path
    fi
  else
    hosts_string="$(echo -e "${hosts_string}" | tr -d '[:space:]')"
    hosts=($(echo "${hosts_string}" | tr ',' '\n'))
  fi
  
  if [ -z "$hosts" ] || [ ${#hosts[@]} -eq 0 ]; then
    echo ""
    error_message "You didn't supply any hosts to export profiles for. Please provide hosts using the --hosts parameter"
    echo ""
    exit 1
  fi
}

report() {
  for host in "${hosts[@]}"
  do
    report_for_host "${host}"
  done
}

report_for_host() {
  local host=$1
  
  # Add the default port (6060) to hosts missing the port component
  if [[ ! $host =~ :[0-9]{4}$ ]]; then
    host="${host}:${default_port}"
  fi

  host_path=${host//\./\-}
  host_path=${host_path//\:/\-}

  tmux_session_id="harmony-pprof-reporting-${host_path}"
  tmux send -t "${tmux_session_id}" C-c
  tmux send -t "${tmux_session_id}" "exit"
  tmux send -t "${tmux_session_id}" Enter
  tmux kill-session -t "${tmux_session_id}" 1> /dev/null 2>&1
  
  echo "Starting to generate reports for host ${host} ..."

  tmux new-session -d -s "${tmux_session_id}"
  local command="bash <(curl -sSL https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/pprof/report.sh) --address ${host} --path pprof/${host_path}"

  echo "Will start dumping pprof reports using the following command: ${command}"
  tmux send -t "${tmux_session_id}" "$command" ENTER

  echo "Tmux session started! Attach to the session using tmux attach-session -t ${tmux_session_id}"
}

run() {
  initialize
  parse_hosts
  report
}

run
