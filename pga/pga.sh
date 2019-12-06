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
  --network         name        name of the network to use - mainnet / pangaea / devnet (dev)
  --addresses       addresses   a list of addresses, comma separated, e.g: one152yn6nvyjuln3kp4m2rljj6hvfapfhdxsmr79a,one1sefnsv9wa4xh3fffmr9f0mvfs7d09wjjnjucuy
  --input-file      path        the file to load wallet addresses from (preferred method)
  --export-file     path        the file to export data to (if the invoked method utilizes exports)
  --amount          amount      the amount used for the invoked method (e.g. for transfers this is the amount that will be sent for each transfer)
  --tx-from         address     the transaction sender address
  --tx-from-shard   shard-id    the transaction sender shard id
  --tx-to           address     the transaction receiver address
  --tx-to-shard     shard-id    the transaction receiver shard id
  --tx-passphrase   passphrase  the passphrase for the wallet - will default to "harmony-one" unless specified for legacy reasons
  --tx-wait         seconds     if you want to use --wait-for-confirm seconds to wait for transactions to finish
  --api-endpoint    url         the API endpoint to use (defaults to https://api.s0.p.hmny.io)
  --verbose                     enable verbose mode
  --help                        print this help section
EOT
}

action=""
while (( "$#" )); do
  case "$1" in
    --network) network="$2" ; shift 2;;
    --addresses) addresses_string="$2" ; shift 2;;
    --input-file) input_file="$2" ; shift 2;;
    --export-file) export_file="$2" ; shift 2 ;;
    --amount) amount="$2" ; shift 2 ;;
    --tx-from) tx_from="$2" ; shift 2 ;;
    --tx-from-shard) tx_from_shard="$2" ; shift 2 ;;
    --tx-to) tx_to="$2" ; shift 2 ;;
    --tx-to-shard) tx_to_shard="$2" ; shift 2 ;;
    --tx-passphrase) tx_passphrase="$2" ; shift 2 ;;
    --tx-wait) tx_wait="$2" ; shift 2 ;;
    --api-endpoint) api_endpoint="$2" ; shift 2 ;;
    --verbose) verbose=true ; shift ;;
    -h|--help) usage; exit 1 ;;
    --) shift; break ;;
    -*|--*=) usage; exit 1 ;;
    *) action="$action $1" ; shift ;;
  esac
done
eval set -- "$action"
action="${action#"${action%%[![:space:]]*}"}"

declare -A total_balances
declare -a export_data

initialize() {
  if [ -z "$network" ]; then
    network="pangaea"
  fi
  
  case $network in
  main|mainnet)
    chain_id=mainnet
    if [ -z "$api_endpoint" ]; then
      api_endpoint="https://api.s0.t.hmny.io"
    fi
    ;;
  pga|pangaea|testnet)
    chain_id=testnet
    if [ -z "$api_endpoint" ]; then
      api_endpoint="https://api.s0.p.hmny.io"
    fi
    ;;
  dev|devnet)
    chain_id=pangaea
    if [ -z "$api_endpoint" ]; then
      api_endpoint="https://api.s0.pga.hmny.io"
    fi
    ;;
  *)
    ;;
  esac
  
  if [ ! -z "$amount" ]; then
    convert_to_integer "$amount"
    amount=$converted
  fi
  
  if [ -z "$tx_passphrase" ]; then
    tx_passphrase="harmony-one"
  fi
  
  if [ -z "$verbose" ]; then
    verbose=false
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
    if [ ! -z "$input_file" ] && test -f $input_file; then
      IFS=$'\n' read -d '' -r -a addresses < $input_file
    fi
  else
    addresses_string="$(echo -e "${addresses_string}" | tr -d '[:space:]')"
    addresses=($(echo "${addresses_string}" | tr ',' '\n'))
  fi
}

transfer() {
  if [ -n "$tx_from" ] && [ -n "$tx_from_shard" ] && [ -n "$tx_to_shard" ] && [ -n "$amount" ]; then
    if [ -n "$addresses" ] || [ ${#addresses[@]} -gt 0 ]; then
      for address in "${addresses[@]}"; do
        send_transaction "$address"
      done
    else
      if [ -n "$tx_to" ]; then
        send_transaction "$tx_to"
      else
        error_message "Missing some arguments! Please provide a receiver address using --tx-to"
      fi
    fi
    
    if [ -n "$export_file" ] && (( ${#export_data[@]} )); then
      export_data=( "address,txhash,status" "${export_data[@]:0}" )
      rm -rf $export_file
      touch $export_file
      printf "%s\n" "${export_data[@]}" > $export_file
    fi

  else
    error_message "Missing some arguments! Please provide values for --tx-from, --tx-from-shard, --tx-to-shard, --amount"
  fi
}

send_transaction() {
  local receiver_address=$1
  
  info_message "Sending transaction from $tx_from (shard id: $tx_from_shard) to $receiver_address (shard id: $tx_to_shard), amount: $amount, chain id: $chain_id"

  tx_command="transfer --from $tx_from --from-shard $tx_from_shard --to $receiver_address --to-shard $tx_to_shard --amount $amount --chain-id $chain_id --passphrase $tx_passphrase"

  if [ ! -z "$tx_wait" ]; then
    tx_command="$tx_command --wait-for-confirm $tx_wait"
  fi

  api_command "$tx_command"
  
  parse_tx
}

parse_tx() {
  if [ -n "$api_response" ]; then
    status=$(echo "${api_response}" | jq ".result.status" | tr -d '"')
    transaction_hash=$(echo "${api_response}" | jq ".result.transactionHash" | tr -d '"')
    
    if [ -n "$transaction_hash" ] && [ ! "$transaction_hash" = "null" ]; then
      if [ "$status" = "0x1" ]; then
        success_message "Transaction ${transaction_hash} was successful!"
        echo
        export_data+=("${receiver_address},${transaction_hash},success")
      else
        info_message "Transaction ${transaction_hash} failed!"
        echo
        export_data+=("${receiver_address},,failed")
      fi
    
    else
      transaction_hash=$(echo "${api_response}" | jq '.["transaction-receipt"]' | tr -d '"')
      
      if [ -n "$transaction_hash" ] && [ ! "$transaction_hash" = "null" ]; then
        info_message "Received transaction receipt: ${transaction_hash} - transaction is in a pending state"
        echo
        export_data+=("${receiver_address},${transaction_hash},pending")
      fi
    fi
    
  else
    info_message "Transaction failed!"
    echo
    export_data+=("${receiver_address},,failed")
  fi
}

verify_exact_balances() {
  if [ -z "$amount" ]; then
    error_message "You need to specify an amount using --amount !"
    exit 1
  fi
  
  balances
  
  for wallet in "${!total_balances[@]}"; do
    total_balance=${total_balances[$wallet]}
    
    if (( total_balance < amount )); then
      echo "Wallet $wallet has a balance lesser than $amount! Total balance is $total_balance"
      export_data+=("${wallet}")
    fi
  done
  
  if [ -n "$export_file" ] && (( ${#export_data[@]} )); then
    rm -rf $export_file
    touch $export_file
    printf "%s\n" "${export_data[@]}" > $export_file
  fi
}

verify_addresses_have_been_provided() {
  if [ -z "$addresses" ] || [ ${#addresses[@]} -eq 0 ]; then
    error_message "You didn't provide any addresses to use together with the commands, please specify either a file using --file or a set of addresses using --addresses"
    exit 1
  fi
}

balances() {
  verify_addresses_have_been_provided
  
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
  local cmd="./hmy --node=$api_endpoint $1"
  
  if [ "$verbose" = true ]; then
    #cmd="$cmd --verbose"
    info_message "Executing api command: $cmd"
  fi
  
  api_response=$($cmd)
  
  if [ "$verbose" = true ]; then
    info_message "Api response: $api_response"
    echo
  fi
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
  echo
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
