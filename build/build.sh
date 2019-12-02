#!/bin/bash

# Harmony custom build script - compiles bleeding edge binaries based on the latest master (or user specified) branch of the harmony and go-sdk git repositories
version="0.0.1"
script_name="build.sh"
default_go_version="go1.12"

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
   --harmony-branch           name    which git branch to use for the harmony, bls and mcl git repositories (defaults to master)
   --hmy-branch               name    which git branch to use for the go-sdk/hmy git repository (defaults to master)
   --help                             print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --path) build_path="${2%/}" ; shift;;
  --go-path) go_path="${2%/}" ; shift;;
  --gvm) install_using_gvm=true ;;
  --go-version) go_version="$2" ; shift;;
  --harmony-branch) harmony_branch="$2" ; shift;;
  --hmy-branch) hmy_branch="$2" ; shift;;
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
    build_path=$HOME/harmony
  fi

  if [ -z "$go_path" ]; then
    go_path=$HOME/go
  fi
  
  if [ -z "$go_version" ]; then
    go_version=$default_go_version
  fi
  
  if [ -z "$harmony_branch" ]; then
    harmony_branch="master"
  fi
  
  if [ -z "$hmy_branch" ]; then
    hmy_branch="master"
  fi
  
  executing_user=$(whoami)
  
  organization="harmony-one"
  repositories=(mcl bls harmony go-sdk)
  packages=(curl build-essential libgmp-dev libssl-dev bison)
  
  if [ "$install_using_gvm" = true ]; then
    packages+=(bison libbison-dev m4)
  fi
  
  repositories_path=$go_path/src/github.com/$organization
  profile_file=".bash_profile"
}

create_base_directories() {
  mkdir -p $repositories_path
}

#
# Dependencies
#
check_dependencies() {
  output_header "${header_index}. Installation - installing missing dependencies (if not already installed)"
  ((header_index++))
  
  info_message "Updating apt-get..."
  
  sudo apt-get update -y --fix-missing >/dev/null 2>&1
  
  success_message "apt-get updated!"
  
  for package in "${packages[@]}"; do
    install_package_dependency "$package"
  done
}

install_package_dependency() {
  package_name=$1

  if ! dpkg-query -W $package_name >/dev/null 2>&1; then
    info_message "${package_name} wasn't detected on your system, proceeding to install it (this might take a while)..."
    sudo apt-get -y install $package_name >/dev/null 2>&1
    success_message "$package_name successfully installed!"
  else
    success_message "$package_name is already installed - proceeding!"
  fi
  
  echo
}

#
# Go installation
#
set_go_version() {
  # This is disabled for now - Harmony specifically depends on go1.12.0 and this code would set the go version to the latest available version fetched from golang.org
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
  output_header "${header_index}. Installation - installing Go version ${go_version} (if not already installed)"
  ((header_index++))
  
  source_environment_variable_scripts
  
  if command -v go >/dev/null 2>&1 || test -d /usr/local/go/bin; then
    detected_go_version=$(go version)
    detected_go_installation_path=$(which go)
    success_message "Successfully found go on your system!"
    success_message "Your go installation is installed in: ${detected_go_installation_path}"
    success_message "You're running version: ${detected_go_version}"
    
    if [ $go_version != $detected_go_version ]; then
      error_message "You're running a go version different than the required version ${go_version} - please make sure ${go_version} installed and that it's the active version."
      exit 1
    fi
    
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
    #set_go_version
    output_sub_header "Installation - installing Go version ${go_version} using the regular go install method"
    
    info_message "Downloading go installation archive..."
  
    curl -LOs https://dl.google.com/go/$go_version.linux-amd64.tar.gz
    sudo tar -xzf $go_version.linux-amd64.tar.gz -C /usr/local
    rm -rf $go_version.linux-amd64.tar.gz
    
    touch $HOME/$profile_file
    
    if ! cat $HOME/$profile_file | grep "export GOROOT" > /dev/null; then
      echo "export GOROOT=/usr/local/go" >> $HOME/$profile_file
    fi
  
    if ! cat $HOME/$profile_file | grep "export GOPATH" > /dev/null; then
      echo "export GOPATH=$go_path" >> $HOME/$profile_file
    fi
  
    echo "export PATH=\$PATH:\$GOROOT/bin" >> $HOME/$profile_file

    source $HOME/$profile_file
  
    success_message "Go version ${go_version} successfully installed!"
    
    output_footer
  fi
}

gvm_go_installation() {
  #set_go_version
  output_sub_header "Installation - installing GVM and Go version ${go_version} using GVM"
  
  sudo rm -rf $HOME/.gvm
  touch $HOME/$profile_file
  
  info_message "Installing GVM..."

  source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
  source $HOME/.gvm/scripts/gvm
  
  if ! cat $HOME/$profile_file | grep ".gvm/scripts/gvm" > /dev/null; then
    echo "[[ -s "\$HOME/.gvm/scripts/gvm" ]] && source \"\$HOME/.gvm/scripts/gvm\"" >> $HOME/$profile_file
  fi
  
  if ! cat $HOME/$profile_file | grep "export GOPATH" > /dev/null; then
    echo "export GOPATH=$go_path" >> $HOME/$profile_file
  fi

  source $HOME/$profile_file
  
  success_message "GVM successfully installed!"
  
  info_message "Installing go version ${go_version}..."

  gvm install $go_version -B
  gvm use $go_version --default
  
  success_message "Go version ${go_version} successfully installed!"
  
  output_footer
}

source_environment_variable_scripts() {
  if test -f $HOME/.gvm/scripts/gvm; then
    source $HOME/.gvm/scripts/gvm
  fi
  
  if test -f $HOME/$profile_file; then
    source $HOME/$profile_file
  fi
}


#
# Build/compilation
#
install_git_repos() {
  output_header "${header_index}. Git - fetching the latest versions of all required git repositories"
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
    git clone https://github.com/${organization}/${repo_name} >/dev/null 2>&1
    cd $repo_name
    update_git_repo
  fi
  
  cleanup_previous_build
}

update_git_repo() {
  git fetch >/dev/null 2>&1
  
  case $repo_name in
  harmony|bls|mcl)
    info_message "Updating git repo ${repo_name} using branch ${harmony_branch}"
    git checkout --force $harmony_branch >/dev/null 2>&1
    git pull >/dev/null 2>&1
    success_message "Successfully installed/updated git repo ${repo_name} using branch ${harmony_branch}"
    ;;
  go-sdk)
    info_message "Updating git repo ${repo_name} using branch ${hmy_branch}"
    git checkout --force $hmy_branch >/dev/null 2>&1
    git pull >/dev/null 2>&1
    success_message "Successfully installed/updated git repo ${repo_name} using branch ${hmy_branch}"
    ;;
  *)
    ;;
  esac
  
  echo
}

cleanup_previous_build() {
  case $repo_name in
  harmony)
    rm -rf $repositories_path/$repo_name/bin/*
    ;;
  go-sdk)
    rm -rf $repositories_path/$repo_name/dist/*
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
  
  cd $repositories_path/harmony && make >/dev/null 2>&1
  
  if test -f bin/harmony; then
    success_message "Successfully compiled harmony, bls and mcl binaries!"
    cp -R bin/* $build_path
    cp $repositories_path/bls/lib/libbls384_256.so $build_path
    cp $repositories_path/mcl/lib/libmcl.so $build_path
    success_message "The compiled binaries are now located in ${build_path}"
    echo
  fi
  
  info_message "Starting compilation of hmy (this can take a while - sometimes several minutes)..."
  
  export GOPATH=$go_path
  
  cd $repositories_path/go-sdk && make >/dev/null 2>&1
  
  if test -f dist/hmy; then
    success_message "Successfully compiled hmy!"
    cp -R dist/* $build_path
    success_message "The compiled binary is now located in ${build_path}"
    echo
  fi
  
  output_footer
}

#
# Scripts
#
download_node_script() {
  cd $build_path
  curl -O --silent --output /dev/null https://raw.githubusercontent.com/harmony-one/harmony/$harmony_branch/scripts/node.sh
  chmod u+x node.sh
  cd - >/dev/null 2>&1
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
  echo
  echo "${italic_text}${1}${normal_text}:"
  echo
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
build() {
  initialize
  check_dependencies
  install_go
  install_git_repos
  compile_binaries
  download_node_script
}

build
