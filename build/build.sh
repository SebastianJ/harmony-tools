#!/bin/bash

# Harmony custom build script - compiles bleeding edge binaries based on the latest master repo
version="0.0.1"
script_name="build.sh"
default_go_version="go1.12.0"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --path                     path    the output path for compiled binaries
   --go-path                  path    the go path where git repositories should be cloned, will default to $GOPATH
   --gvm                              install go using gvm
   --go-version                       what version of golang to install, defaults to ${default_go_version}
   --help                             print this help
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --path) build_path="${2%/}" ; shift;;
  --go-path) go_path="${2%/}" ; shift;;
  --gvm) install_using_gvm=true ;;
  --go-version) go_version="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

initialize() {
  set_variables
  create_base_directories  
  set_formatting
}

set_variables() {  
  if [ -z "$install_using_gvm" ]; then
    install_using_gvm=false
  fi
  
  if [ -z "$build_path" ]; then
    build_path=$HOME/harmony-binaries
  fi

  if [ -z "$go_path" ]; then
    go_path=$HOME/go
  fi
  
  executing_user=$(whoami)
  
  organization="harmony-one"
  repositories=(mcl bls harmony go-sdk)
  binary_repositories=(harmony go-sdk)
  repositories_path=$go_path/src/github.com/$organization
}

create_base_directories() {
  mkdir -p $repositories_path
}

#
# Dependencies
#
check_dependencies() {
  install_build_essentials
}

install_build_essentials() {
  build_essentials_installed=$(dpkg-query -l build-essential | grep -oam 1 "no packages found")
  
  if [ ! -z "$build_essentials_installed" ]; then
    info_message "build-essential wasn't detected on your system, proceeding to install it"
    sudo apt-get -y install build-essential
    
    build_essentials_installed=$(dpkg-query -l build-essential | grep -oam 1 "no packages found")
    
    if [ -z "$build_essentials_installed" ]; then
      success_message "build-essential successfully installed!"
    fi
  fi
}


#
# Go installation
#
set_go_version() {
  if [ -z "$go_version" ]; then
    latest_go_version=$(curl -sS https://golang.org/VERSION?m=text)
    
    if [ ! -z "$latest_go_version" ]; then
      go_version=$latest_go_version
    else
      go_version=$default_go_version
    fi
  fi
}

install_go() {
  output_header "${header_index}. Installation - installing go if not already installed"
  ((header_index++))
  
  source_environment_variable_scripts
  
  if command -v go >/dev/null 2>&1; then
    go_version=$(go version)
    go_installation_path=$(which go)
    success_message "Successfully found go on your system!"
    success_message "Your go installation is installed in: ${go_installation_path}"
    success_message "You're running version: ${go_version}"
  else
    info_message "Can't detect go on your system! Proceeding to install..."
    
    if [ "$install_using_gvm" = true ]; then
      gvm_go_installation
    else
      regular_go_installation
    fi
  fi
  
  output_footer
}

regular_go_installation() {
  if ! test -d /usr/local/go/bin; then
    set_go_version
  
    output_header "${header_index}. Installation - installing Go version ${go_version} using regular install"
    ((header_index++))
    
    info_message "Downloading go installation archive..."
  
    curl -LOs https://dl.google.com/go/$go_version.linux-amd64.tar.gz
    sudo tar -xzf $go_version.linux-amd64.tar.gz -C /usr/local
    rm -rf $go_version.linux-amd64.tar.gz
    
    touch $HOME/.bashrc
    
    if ! cat $HOME/.bashrc | grep "export GOROOT" > /dev/null; then
      echo "export GOROOT=/usr/local/go" >> $HOME/.bashrc
    fi
  
    if ! cat $HOME/.bashrc | grep "export GOPATH" > /dev/null; then
      echo "export GOPATH=$go_path" >> $HOME/.bashrc
    fi
  
    echo "export PATH=\$PATH:\$GOROOT/bin" >> $HOME/.bashrc

    source $HOME/.bashrc
  
    success_message "Go version ${go_version} successfully installed!"
    
    output_footer
  fi
}

gvm_go_installation() {
  set_go_version
  
  output_header "${header_index}. Installation - installing GVM and Go version ${go_version} using GVM"
  ((header_index++))
  
  sudo rm -rf $HOME/.gvm
  touch $HOME/.bashrc
  
  info_message "Installing GVM"

  source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer) 1> /dev/null 2>&1
  source $HOME/.gvm/scripts/gvm
  
  if ! cat $HOME/.bashrc | grep ".gvm/scripts/gvm" > /dev/null; then
    echo "[[ -s "\$HOME/.gvm/scripts/gvm" ]] && source \"\$HOME/.gvm/scripts/gvm\"" >> $HOME/.bashrc
  fi
  
  if ! cat $HOME/.bashrc | grep "export GOPATH" > /dev/null; then
    echo "export GOPATH=$go_path" >> $HOME/.bashrc
  fi

  source $HOME/.bashrc
  
  success_message "GVM successfully installed!"
  
  info_message "Installing go version ${go_version}..."

  gvm install $go_version -B 1> /dev/null 2>&1
  gvm use $go_version --default 1> /dev/null 2>&1
  
  success_message "Go version ${go_version} successfully installed!"
  
  output_footer
}

source_environment_variable_scripts() {
  if test -f $HOME/.gvm/scripts/gvm; then
    source $HOME/.gvm/scripts/gvm
  fi
  
  source $HOME/.bashrc
}


#
# Build/compilation
#
install_git_repos() {
  output_header "${header_index}. Git - fetching the latest master versions of all required git repositories"
  ((header_index++))
  
  for repo in "${repositories[@]}"; do
    install_git_repo $repo
  done
  
  output_footer
}

install_git_repo() {
  repo_name="${1}"
  
  mkdir -p $repositories_path
  cd $repositories_path
  
  if test -d $repo_name; then
    cd $repo_name
    update_git_repo
  else
    git clone https://github.com/${organization}/${repo_name} 1> /dev/null 2>&1
    cd $repo_name
    update_git_repo
  fi
  
  cleanup_previous_build
}

update_git_repo() {
  git fetch 1> /dev/null 2>&1
  git checkout --force master 1> /dev/null 2>&1
  git pull 1> /dev/null 2>&1
  success_message "Successfully installed/updated the repo ${repo_name}"
}

cleanup_previous_build() {
  case $repo_name in
  harmony|go-sdk)
    rm -rf $repositories_path/$repo_name/bin/*
    ;;
  bls|mcl)
    rm -rf $repositories_path/$repo_name/lib/*
    ;;
  *)
    ;;
  esac
}

#
# Compilation
#
compile_binaries() {
  output_header "${header_index}. Build - compiling binaries"
  ((header_index++))
  
  info_message "Starting compilation of harmony, bls and mcl binaries (this can take a while - sometimes several minutes)..."
  
  rm -rf $build_path
  mkdir -p $build_path
  
  cd $repositories_path/harmony && make 1> /dev/null 2>&1
  
  if test -f bin/harmony; then
    success_message "Successfully compiled harmony, bls and mcl binaries!"
    cp -R bin/* $build_path
    cp $repositories_path/bls/lib/libbls384_256.so $build_path
    cp $repositories_path/mcl/lib/libmcl.so $build_path
    success_message "The compiled binaries are now located in ${build_path}"
  fi
  
  info_message "Starting compilation of hmy (this can take a while - sometimes several minutes)..."
  
  export GOPATH=$go_path
  
  cd $repositories_path/go-sdk && make 1> /dev/null 2>&1
  
  if test -f dist/hmy; then
    success_message "Successfully compiled hmy!"
    cp -R dist/* $build_path
    success_message "The compiled binary is now located in ${build_path}"
  fi
  
  output_footer
}

#
# Formatting/outputting methods
#
set_formatting() {
  header_index=1
  
  bold_text=$(tput bold)
  italic_text=$(tput sitm)
  normal_text=$(tput sgr0)
  black_text=$(tput setaf 0)
  red_text=$(tput setaf 1)
  green_text=$(tput setaf 2)
  yellow_text=$(tput setaf 3)
}

info_message() {
  echo -e "${1}"
}

success_message() {
  echo ${green_text}${1}${normal_text}
}

warning_message() {
  echo ${yellow_text}${1}${normal_text}
}

error_message() {
  echo ${red_text}${1}${normal_text}
}

output_separator() {
  echo "------------------------------------------------------------------------"
}

output_banner() {
  output_header "Running Harmony build script v${version}"
  current_time=`date`  
  info_message "You're running ${bold_text}${script_name}${normal_text} as ${bold_text}${executing_user}${normal_text}. Current time is: ${bold_text}${current_time}${normal_text}."
}

output_header() {
  echo
  output_separator
  echo "${bold_text}${1}${normal_text}"
  output_separator
  echo
}

output_sub_header() {
  echo "${italic_text}${1}${normal_text}:"
}

output_footer() {
  echo
  output_separator
}

output_sub_footer() {
  echo
}

#
# Main function
#
run() {
  initialize
  check_dependencies
  install_go
  install_git_repos
  compile_binaries
}

run
