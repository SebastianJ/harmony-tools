#!/bin/bash

version="0.0.1"
script_name="pga.sh"

usage() {
   cat << EOT
Usage: $0 command [options]
Commands:
  transfer                    transfer tokens to provided addresses
  balances                    check balances for provided addresses
  verify-exact-balances       verify exact balances for provided addresses

Options:
  --addresses     addresses   a list of addresses, comma separated, e.g: one152yn6nvyjuln3kp4m2rljj6hvfapfhdxsmr79a,one1sefnsv9wa4xh3fffmr9f0mvfs7d09wjjnjucuy
  --file          path        the file to load wallet addresses from (preferred method)
  --export-file   path        the file to export data to (if the invoked method utilizes exports)
  --amount        amount      the amount used for the invoked method (e.g. for transfers this is the amount that will be sent for each transfer)
  --api_endpoint  url         the API endpoint to use (defaults to https://api.s0.p.hmny.io)
  --help                      print this help section
EOT
}

action=""
while (( "$#" )); do
  case "$1" in
    --addresses) addresses_string="$2" ; shift 2;;
    --file) file_path="$2" ; shift 2;;
    --export-file) export_file="$2" ; shift 2 ;;
    --amount) amount="$2" ; shift 2 ;;
    --endpoint) api_endpoint="$2" ; shift 2 ;;
    -h|--help) usage; exit 1 ;;
    --) shift; break ;;
    -*|--*=) usage; exit 1 ;;
    *) action="$action $1" ; shift ;;
  esac
done
eval set -- "$action"
action="${action#"${action%%[![:space:]]*}"}"

declare -A total_balances

initialize() {
  if [ -z "$api_endpoint" ]; then
    api_endpoint="https://api.s0.p.hmny.io"
  fi
  
  if [ ! -z "$amount" ]; then
    convert_to_integer "$amount"
    amount=$converted
  fi
  
  if [ -z "$export_file" ]; then
    export_file="export.txt"
  fi
  
  packages=(curl jq)
  
  executing_user=$(whoami)
  
  set_formatting
}

check_dependencies() {
  for package in "${packages[@]}"; do
    install_package_dependency "$package"
  done
  
  install_hmy
}

install_hmy() {
  if ! test -f hmy; then
    info_message "Couldn't find hmy on your system - proceeding to download it..."
    curl -LO https://harmony.one/hmycli && mv hmycli hmy && chmod u+x hmy
    
    if test -f hmy; then
      success_message "Successfully installed hmy!"
    fi
  fi
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
    echo
  fi
}

parse_addresses() {
  if [ -z "$addresses_string" ]; then
    if [ ! -z "$file_path" ] && test -f $file_path; then
      IFS=$'\n' read -d '' -r -a addresses < $file_path
    fi
  else
    addresses_string="$(echo -e "${addresses_string}" | tr -d '[:space:]')"
    addresses=($(echo "${addresses_string}" | tr ',' '\n'))
  fi
  
  if [ -z "$addresses" ] || [ ${#addresses[@]} -eq 0 ]; then
    error_message "You didn't provide any addresses to use together with the commands, please specify either a file using --file or a set of addresses using --addresses"
    exit 1
  fi
}

transfer() {
  echo "To be implemented!"
  exit 1
}

verify_exact_balances() {
  if [ -z "$amount" ]; then
    error_message "You need to specify an amount using --amount !"
    exit 1
  fi
  
  balances
  declare -a export_wallets
  
  for wallet in "${!total_balances[@]}"; do
    total_balance=${total_balances[$wallet]}
    
    if (( total_balance < amount )); then
      echo "Wallet $wallet has a balance lesser than $amount! Total balance is $total_balance"
      export_wallets+=("${wallet}")
    fi
  done
  
  if (( ${#export_wallets[@]} )); then
    touch $export_file
    printf "%s\n" "${export_wallets[@]}" > $export_file
  fi
}

balances() {
  for address in "${addresses[@]}"; do
    check_balance_for_address
  done
}

check_balance_for_address() {
  info_message "Checking balances for wallet ${address}"
  api_command "balances $address"
  
  declare -a totals
    
  for row in $(echo "${api_response}" | jq -c '.[]'); do
    shard=$(echo $row | jq -c '.shard')
    balance=$(echo $row | jq -c '.amount')
    convert_to_integer "$balance"
    balance=$converted
    (( totals += balance ))
    echo "Balance for $address in shard $shard is $balance"
  done
  
  echo "Total balance for $address in all shards is ${totals}"
  echo
  
  total_balances[$address]=$totals
}

api_command() {
  local cmd=$1
  api_response=$(./hmy --node=$api_endpoint $cmd)
}

#
# Helpers
#
convert_to_integer() {
  local number=$1
  number=${number%.*}  
  converted=$((10#$number))
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
  output_header "Running pga.sh: Pangaea tool v${version}"
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

output_footer() {
  echo
  output_separator
}

run() {
  initialize
  output_banner
  check_dependencies
  parse_addresses

  case "$action" in
    "transfer") transfer ;;
    "balances") balances ;;
    "verify-exact-balances") verify_exact_balances ;;
    *) usage ;;
  esac
}

run
