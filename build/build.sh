#!/bin/bash

# Harmony custom build script - compiles latest master (or user specified) branch of the harmony, bls, mcl, go-sdk and harmony-tui git repos
version="0.0.2"
script_name="build.sh"
default_go_version="go1.13.7"

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
   --branch           name    which git branch to use for the harmony-one/harmony repo (defaults to master)
   --bls-branch               name    which git branch to use for the harmony-one/bls repo (defaults to master)
   --mcl-branch               name    which git branch to use for the harmony-one/mcl repo (defaults to master)
   --hmy-branch               name    which git branch to use for the harmony-one/go-sdk repo (defaults to master)
   --tui-branch               name    which git branch to use for the harmony-one/harmony-tui repo (defaults to master)
   --enable-double-signing            enables double-signing behavior by using github.com/SebastianJ/harmony/enable-double-signing
   --race                             enables -race compilation of the harmony binary
   --upload                           if the script should upload the compiled binaries to S3
   --s3-url                           what s3 base url to use for uploading binaries (defaults to s3://tools.harmony.one/release/linux-x86_64/harmony)
   --apt-get-update                   if apt-get update should run
   --verbose                          run the script in verbose mode
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
  --branch) harmony_branch="$2" ; shift;;
  --bls-branch) bls_branch="$2" ; shift;;
  --mcl-branch) mcl_branch="$2" ; shift;;
  --hmy-branch) hmy_branch="$2" ; shift;;
  --tui-branch) tui_branch="$2" ; shift;;
  --enable-double-signing) enable_double_signing=true ;;
  --race) enable_race_compilation=true ;;
  --upload) should_upload_to_s3=true ;;
  --s3-url) s3_url="$2" ; shift;;
  --verbose) verbose=true ;;
  --apt-get-update) run_apt_get_update=true ;;
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
  executing_user=$(whoami)
  organization="harmony-one"
  harmony_repo_organization="harmony-one"  
  profile_file=".bash_profile"
  double_signing_branch="enable-double-signing"

  if [ -z "$install_using_gvm" ]; then
    install_using_gvm=false
  fi

  if [ -z "$should_upload_to_s3" ]; then
    should_upload_to_s3=false
  fi

  if [ -z "$enable_double_signing" ]; then
    enable_double_signing=false
  fi

  if [ -z "$enable_race_compilation" ]; then
    enable_race_compilation=false
  fi

  if [ -z "$run_apt_get_update" ]; then
    run_apt_get_update=false
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

  if [ -z "$bls_branch" ]; then
    bls_branch="master"
  fi

  if [ -z "$mcl_branch" ]; then
    mcl_branch="master"
  fi
  
  if [ -z "$hmy_branch" ]; then
    hmy_branch="master"
  fi

  if [ -z "$tui_branch" ]; then
    tui_branch="master"
  fi

  if [ -z "$revert_harmony_commit" ]; then
    revert_harmony_commit=""
  fi

  if [ -z "$revert_harmony_commit_branch" ]; then
    revert_harmony_commit_branch=""
  fi

  if [ -z "$build_path" ]; then
    build_path=$HOME/harmony/build/dist/$harmony_branch
  fi

  if [ -z "$s3_url" ]; then
    s3_url="s3://tools.harmony.one/release/linux-x86_64/harmony/${harmony_branch}"
  fi

  if [ "$enable_double_signing" = true ]; then
    build_path=$build_path/enable-double-signing
    s3_url=$s3_url/enable-double-signing
    harmony_repo_organization="SebastianJ"
  fi

  if [ "$enable_race_compilation" = true ]; then
    build_path=$build_path/race
    s3_url=$s3_url/race
  fi

  repositories_path=$go_path/src/github.com/$organization
  harmony_repositories_path=$go_path/src/github.com/$harmony_repo_organization
  
  harmony_repos=(mcl bls harmony)
  tools_repos=(go-sdk) # Skip harmony-tui for now - can't build a static binary using make linux_static
  
  packages=(curl build-essential libgmp-dev libssl-dev bison)
  if [ "$install_using_gvm" = true ]; then
    packages+=(bison libbison-dev m4)
  fi

  binaries=(harmony bootnode hmy)
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
  
  if [ "$run_apt_get_update" = true ]; then
    info_message "Updating apt-get..."
    
    if [ "$verbose" = true ]; then
      sudo apt-get update -y --fix-missing
    else
      sudo apt-get update -y --fix-missing >/dev/null 2>&1
    fi
  fi
  
  success_message "apt-get updated!"
  
  for package in "${packages[@]}"; do
    install_package_dependency "$package"
  done
}

install_package_dependency() {
  package_name=$1

  if ! dpkg-query -W $package_name >/dev/null 2>&1; then
    info_message "${package_name} wasn't detected on your system, proceeding to install it (this might take a while)..."
    
    if [ "$verbose" = true ]; then
      sudo apt-get -y install $package_name
    else
      sudo apt-get -y install $package_name >/dev/null 2>&1
    fi
    
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
    
    if [[ ! "$detected_go_version" =~ "$go_version" ]]; then
      error_message "You're running a go version (${detected_go_version}) different than the required version ${go_version} - please make sure ${go_version} installed and that it's the active version."
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
    set_go_version
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
  set_go_version
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
# Git
#
install_git_repos() {
  output_header "${header_index}. Git - fetching the latest versions of all required git repositories"
  ((header_index++))
  
  for repo in "${harmony_repos[@]}"; do
    install_git_repo "$harmony_repositories_path" "$harmony_repo_organization" "$repo"
  done

  for repo in "${tools_repos[@]}"; do
    install_git_repo "$repositories_path" "$organization" "$repo"
  done
  
  output_footer
}

install_git_repo() {
  local current_repositories_path="${1}"
  local current_organization="${2}"
  local repo_name="${3}"
  
  mkdir -p $current_repositories_path
  cd $current_repositories_path
  
  if test -d $repo_name; then
    cd $repo_name
    update_git_repo "${repo_name}"
  else
    if [ "$verbose" = true ]; then
      git clone https://github.com/${current_organization}/${repo_name}
    else
      git clone https://github.com/${current_organization}/${repo_name} >/dev/null 2>&1
    fi
    
    cd $repo_name
    update_git_repo "${repo_name}"
  fi
}

update_git_repo() {
  local repo_name="${1}"

  git fetch >/dev/null 2>&1
  
  case $repo_name in
  harmony)
    update_specific_git_repo "${repo_name}" "${harmony_branch}"
    if [ "$enable_double_signing" = true ]; then
      merge_double_signing_functionality "${repo_name}" "${harmony_branch}"
    fi
    ;;
  bls)
    update_specific_git_repo "${repo_name}" "${bls_branch}"
    ;;
  mcl)
    update_specific_git_repo "${repo_name}" "${mcl_branch}"
    ;;
  go-sdk)
    update_specific_git_repo "${repo_name}" "${hmy_branch}"
    ;;
  harmony-tui)
    update_specific_git_repo "${repo_name}" "${tui_branch}"
    ;;
  *)
    ;;
  esac
  
  echo
}

update_specific_git_repo() {
  local repo_name="${1}"
  local git_branch="${2}"

  info_message "Updating git repo ${repo_name} using branch ${git_branch}"
    
  if [ "$verbose" = true ]; then
    git checkout --force $git_branch
    git pull
  else
    git checkout --force $git_branch >/dev/null 2>&1
    git pull >/dev/null 2>&1
  fi

  success_message "Successfully installed/updated git repo ${repo_name} using branch ${git_branch}"
}

merge_double_signing_functionality() {
  local repo_name="${1}"
  local git_branch="${2}"

  if [ "$verbose" = true ]; then
    git checkout --force $double_signing_branch
    git merge --strategy=ours --message "compile" $git_branch
    git checkout $git_branch
    git merge --message "compile" $double_signing_branch
  else
    git checkout --force $double_signing_branch >/dev/null 2>&1
    git merge --strategy=ours --message "compile" $git_branch >/dev/null 2>&1
    git checkout $git_branch >/dev/null 2>&1
    git merge --message "compile" $double_signing_branch >/dev/null 2>&1
  fi
}

cleanup_double_signing_functionality() {
  if [ "$enable_double_signing" = true ]; then
    cd $harmony_repositories_path/harmony

    if [ "$verbose" = true ]; then  
      git stash
    else
      git stash >/dev/null 2>&1
    fi
  fi
}

revert_specific_commit() {
  local repo_name="${1}"
  local git_branch="${2}"
  local specific_commit="${3}"
  
  if [ ! -z "$specific_commit" ]; then
    info_message "Reverting commit '${specific_commit}' in ${repo_name} (${git_branch})"
    info_message "Will create the branch '${revert_harmony_commit_branch}' for the purpose of reversing the commit '${specific_commit}'"
    if [ "$verbose" = true ]; then
      git branch -D $revert_harmony_commit_branch
      git checkout --force -b $revert_harmony_commit_branch $git_branch
      git revert $specific_commit
    else
      git branch -D $revert_harmony_commit_branch >/dev/null 2>&1
      git checkout --force -b $revert_harmony_commit_branch $git_branch >/dev/null 2>&1
      git revert $specific_commit >/dev/null 2>&1
    fi
  fi
}

cleanup_git_revert_branch() {
  local repo_name="${1}"

  if [ ! -z "$specific_commit" ]; then
    info_message "Cleaning up special revert commit branch '${revert_harmony_commit_branch}' in harmony-one/harmony (based on branch: ${harmony_branch})"
    cd $repositories_path/harmony

    if [ "$verbose" = true ]; then
      git checkout --force master
      git branch -D $revert_harmony_commit_branch
    else
      git checkout --force master >/dev/null 2>&1
      git branch -D $revert_harmony_commit_branch >/dev/null 2>&1
    fi
  fi
}

#
# Build / Compilation
#
compile_binaries() {
  output_header "${header_index}. Build - compiling binaries"
  ((header_index++))
  
  rm -rf $build_path
  mkdir -p $build_path
  export GOPATH=$go_path
  
  compile_harmony_binary
  compile_hmy_binary
  #compile_harmony_tui
  
  output_footer
}

compile_harmony_binary() {
  info_message "Starting compilation of harmony, bootnode and wallet binaries (this can take a while - sometimes several minutes)..."
  cd $harmony_repositories_path/harmony

  if [ "$enable_race_compilation" = true ]; then
    if [ "$verbose" = true ]; then
      make -C ../mcl
      make -C ../bls minimised_static BLS_SWAP_G=1
      ./scripts/go_executable_build.sh -s -r
    else
      make -C ../mcl  >/dev/null 2>&1
      make -C ../bls minimised_static BLS_SWAP_G=1  >/dev/null 2>&1
      ./scripts/go_executable_build.sh -s -r  >/dev/null 2>&1
    fi
  else
    if [ "$verbose" = true ]; then
      make linux_static
    else
      make linux_static >/dev/null 2>&1
    fi
  fi

  if test -f bin/harmony; then
    success_message "Successfully compiled harmony, bootnode and wallet binaries!"
    cp -R bin/* $build_path
    success_message "The compiled binaries are now located in ${build_path}"
    echo
  fi
}

compile_hmy_binary() {
  info_message "Starting compilation of hmy (this can take a while - sometimes several minutes)..."
  if [ "$verbose" = true ]; then
    cd $repositories_path/go-sdk && make static
  else
    cd $repositories_path/go-sdk && make static >/dev/null 2>&1
  fi
  
  if test -f dist/hmy; then
    success_message "Successfully compiled hmy!"
    cp -R dist/* $build_path
    success_message "The compiled binary is now located in ${build_path}"
  fi
}

compile_harmony_tui() {
  info_message "Starting compilation of harmony-tui (this can take a while - sometimes several minutes)..."
    
  if [ "$verbose" = true ]; then
    cd $repositories_path/harmony-tui && make linux_static
  else
    cd $repositories_path/harmony-tui && make linux_static >/dev/null 2>&1
  fi
  
  if test -f bin/harmony-tui; then
    success_message "Successfully compiled harmony-tui!"
    cp -R bin/* $build_path
    success_message "The compiled binary is now located in ${build_path}"
    echo
  fi
}

cleanup_previous_build() {
  case $repo_name in
  harmony|harmony-tui)
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
# Upload
#
upload_to_s3() {
  if [ "$should_upload_to_s3" = true ] && [ ! -z "$s3_url" ]; then
    output_header "${header_index}. Upload - uploading binaries to Amazon S3"
    ((header_index++))
  
    cd $build_path

    info_message "Starting to upload binaries from ${build_path} to ${s3_url} ..."
    echo ""

    for binary in "${binaries[@]}"; do
      info_message "Uploading ${binary} to ${s3_url}/${binary} ..."
      aws s3 cp $binary $s3_url/$binary --acl public-read
      echo ""
    done

    output_footer
  fi
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
  output_banner
  check_dependencies
  install_go
  cleanup_previous_build
  install_git_repos
  compile_binaries
  upload_to_s3
  cleanup_double_signing_functionality
}

build
