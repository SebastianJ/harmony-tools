#!/bin/bash

# Harmony double-signing setup
version="0.0.1"
script_name="setup.sh"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --network                    name        what network to run double-signing on (stress, staking)
   --shard                      shard       what shard to start the node on
   --validator-amount           amount      the amount the validator should be created/self-staked with (defaults to 10000)
   --delegator-amount           amount      the amount the delegator should delegate to the validator (defaults to 1000)
   --address                    address     the address of the account that will be used to fund the validator and delegator accounts
   --double-signing-interval    seconds     how many seconds to send double-signing messages
   --gas-price                  price       what gas price to use for transactions (defaults to 1)
   --timeout                    seconds     what shard to start the node on
   --loop                                   run double-signing in an endless loop
   --help                                   print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --network) network="$2" ; shift;;
  --shard) shard="$2" ; shift;;
  --validator-amount) validator_amount="$2" ; shift;;
  --delegator-amount) delegator_amount="$2" ; shift;;
  --address) address="$2" ; shift;;
  --double-signing-interval) double_signing_interval="$2" ; shift;;
  --gas-price) gas_price="$2" ; shift;;
  --timeout) timeout="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

initialize() {
  if [ -z "$network" ]; then
    network="stress"
  fi

  if [ -z "$shard" ]; then
    shard=0
  fi

  if [ -z "$validator_amount" ]; then
    validator_amount=10000
  fi

  if [ -z "$delegator_amount" ]; then
    delegator_amount=1000
  fi

  if [ -z "$address" ]; then
    echo "You must supply an address to use for funding the validator and delegator accounts!"
    exit 1
  fi

  if [ -z "$double_signing_interval" ]; then
    double_signing_interval=240
  fi

  if [ -z "$gas_price" ]; then
    gas_price=1
  fi

  if [ -z "$timeout" ]; then
    timeout=60
  fi

  if [ -z "$loop" ]; then
    loop=false
  fi

  case $network in
    stress)
      node="https://api.s0.stn.hmny.io"
      shard_node="https://api.s${shard}.stn.hmny.io"
      ;;
    staking)
      node="https://api.s0.os.hmny.io"
      shard_node="https://api.s${shard}.os.hmny.io"
      ;;
    *)
      ;;
  esac

  timestamp=$(date +%s)
  node_id="${network}-node-${timestamp}"
  tmux_session_id="harmony-${node_id}"
  validator_account_name="DS-Validator-${timestamp}"
  delegator_account_name="DS-Delegator-${timestamp}"
  packages=(jq tmux curl)
}

check_dependencies() {
  local missing_packages=()

  for package in "${packages[@]}"; do
    if ! command -v "${package}" >/dev/null 2>&1; then
      missing_packages+=($package)
    fi
  done

  if (( ${#missing_packages[@]} )); then
    need_to_install=${missing_packages[@]}
    echo "The following packages need to be installed: ${need_to_install}"
    echo "Please install them using:"

    if command -v apt-get >/dev/null 2>&1; then
      echo "sudo apt-get install -y ${need_to_install}"
    fi

    if command -v yum >/dev/null 2>&1; then
      echo "sudo yum install ${need_to_install}"
    fi
    
    exit 1
  fi
}

check_funding_account() {
  account_exists=`./hmy keys list | grep ${address} | grep -oam 1 -E "(one[a-z0-9]+)" | grep -oam 1 -E "one[a-z0-9]+"`
  if [ -z "$account_exists" ]; then
    echo "Can't find the address ${address} in your keystore - are you sure that you've added it to the keystore?"
    exit 1
  fi
}

check_for_running_node() {
  if ps aux | grep '[h]armony -bootnodes' > /dev/null; then
    echo "You already have a running Harmony node! Please terminate it before running this script"
    echo "Running node:"
    ps aux | grep '[h]armony -bootnodes'
    echo "You can shut down the old node using the below commmand:"
    echo "kill $(ps aux | grep '[h]armony -bootnodes' | awk '{print $2}')"
    echo ""
    exit 1
  fi
}

install_node() {
  mkdir -p $node_id && cd $node_id
  bash <(curl -sSL https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/install/install.sh) --node --enable-double-signing
  bash <(curl -sSL https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/keys/generate.sh) --shard $shard --count 1 --node $node
  bls_key=`ls -d *.key | tail -1 | sed "s|.key||g"`
}

configure_double_signing() {
  # These are dummy values - should probably remove the webhooks from the double-signing binary eventually since they aren't used anyways
  notice_endpoint=https://webhook.site/ed18af8d-9dd5-42dc-a630-1d1ca1d68a30
  double_sign_endpoint=https://webhook.site/ed18af8d-9dd5-42dc-a630-1d1ca1d68a30

  curl -LO https://gist.githubusercontent.com/SebastianJ/e1bc2057faa99870452e60bd56abb576/raw/345fbc0aadf936da76e20fe4714f0225e989e22b/webhooks.yml
  sed -i "s#ENTER_YOUR_BLS_KEY_HERE_WITHOUT_DOT_KEY#${bls_key}#g" webhooks.yml
  sed -i "s#ENTER_DOUBLE_SIGN_NOTICE_ENDPOINT_HERE#${notice_endpoint}#g" webhooks.yml
  sed -i "s#ENTER_THIS_NODE_DOUBLE_SIGNED_ENDPOINT_HERE#${double_sign_endpoint}#g" webhooks.yml

  echo "webhooks.yml now consists of:"
  cat webhooks.yml
  echo ""
  echo ""
}

start_node() {
  local command="./node.sh -k ${bls_key}.key -N ${network} -z -D -S -W webhooks.yml"
  echo "Will start new tmux session with id ${tmux_session_id}"
  
  tmux kill-session -t "${tmux_session_id}" 1> /dev/null 2>&1
  tmux new-session -d -s "${tmux_session_id}" 1> /dev/null 2>&1

  echo "Will start the node using the following command: ${command}"
  tmux send -t "${tmux_session_id}" "$command" ENTER ENTER

  echo "Tmux session started! Attach to the session using tmux attach-session -t ${tmux_session_id}"
}

sync_node() {
  echo "Waiting for node to sync..."
  while true
  do
    local_block_number=$(./hmy blockchain latest-header | jq '.result.blockNumber | tonumber')
    api_block_number=$(./hmy --node ${shard_node} blockchain latest-header | jq '.result.blockNumber | tonumber')
    echo "Current local block number is now ${local_block_number}, remote block number is ${api_block_number}"
    buffer=$((api_block_number - 25))
    
    if (( local_block_number >= buffer )); then
      echo "Node has now synced!"
      break
    else
      sleep 5
    fi
  done
}

setup_accounts() {
  echo "Creating accounts..."
  echo "Creating validator account ${validator_account_name}"
  ./hmy keys add $validator_account_name
  validator_account_address=`./hmy keys list | grep ${validator_account_name} | grep -oam 1 -E "(one[a-z0-9]+)" | grep -oam 1 -E "one[a-z0-9]+"`
  echo "Validator account ${validator_account_name} with address ${validator_account_address} successfully created!"
  echo ""
  
  echo "Creating delegator account ${validator_account_name}"
  ./hmy keys add $delegator_account_name
  delegator_account_address=`./hmy keys list | grep ${delegator_account_name} | grep -oam 1 -E "(one[a-z0-9]+)" | grep -oam 1 -E "one[a-z0-9]+"`
  echo "Delegator account ${delegator_account_name} with address ${delegator_account_address} successfully created!"
  echo ""
}

fund_accounts() {
  validator_funding_amount=$((validator_amount + 1))
  delegation_funding_amount=$((delegator_amount + 1))

  echo "Funding validator address $validator_account_address with amount $validator_funding_amount"
  ./hmy transfer \
    --from $address \
    --from-shard 0 \
    --to $validator_account_address \
    --to-shard 0 \
    --amount $validator_funding_amount \
    --gas-price $gas_price \
    --timeout $timeout \
    --node $node

  if [ ! $? -eq 0 ]; then
    echo "Failed to fund the validator account ${validator_account_address} - please check what happened using ./hmy --node $node failures plain"
    exit 1
  fi

  echo "Funding delegator address $delegator_account_address with amount $delegation_funding_amount"
  ./hmy transfer \
    --from $address \
    --from-shard 0 \
    --to $delegator_account_address \
    --to-shard 0 \
    --amount $delegation_funding_amount \
    --gas-price $gas_price \
    --timeout $timeout \
    --node $node
  
  if [ ! $? -eq 0 ]; then
    echo "Failed to fund the delegator account ${delegator_account_address} - please check what happened using ./hmy --node $node failures plain"
    exit 1
  fi
}

create_validator() {
  max_total_delegation=$((validator_amount + delegator_amount))
  
  echo "Creating the validator..."
  yes "" | ./hmy staking create-validator \
    --validator-addr $validator_account_address \
    --name "TestValidator DS #bot" \
    --identity testvalidator \
    --website justatestvalidator.com \
    --security-contact testvalidator \
    --details "TestValidator DS" \
    --rate 0.01 \
    --max-rate 0.25 \
    --max-change-rate 0.05 \
    --min-self-delegation $validator_amount \
    --max-total-delegation $max_total_delegation \
    --bls-pubkeys $bls_key \
    --amount $validator_amount \
    --gas-price $gas_price \
    --timeout $timeout \
    --node $node 1> /dev/null 2>&1

  if [ ! $? -eq 0 ]; then
    echo "Failed to create the validator with the address ${validator_account_address} - please check what happened using ./hmy --node $node failures staking"
    exit 1
  fi

  echo "Validator created! Validator info:"
  ./hmy blockchain validator information $validator_account_address --node $node | jq
  
  echo "Delegating to the validator..."
  ./hmy staking delegate \
    --delegator-addr $delegator_account_address \
    --validator-addr $validator_account_address \
    --amount $delegator_amount \
    --gas-price $gas_price \
    --timeout $timeout \
    --node $node
  
  validator_info=`./hmy blockchain validator information $validator_account_address --node $node`
  delegations_count=`echo $validator_info | jq '.result.validator.delegations | length | tonumber'`
  total_delegation_before_double_signing=`echo $validator_info | jq '.result["total-delegation"] | tonumber'`
  convert_wei_to_number "${total_delegation_before_double_signing}"
  total_delegation_before_double_signing=$converted
  echo "Total delegation to validator ${validator_account_address} before double-signing is: ${total_delegation_before_double_signing}"
  echo "Number of delegations to validator ${validator_account_address}: ${delegations_count}"

  echo "Checking committee status for validator ${validator_account_address} ..."
  while true
  do
    if `./hmy utility committees --node $node | grep $validator_account_address >/dev/null`; then
      echo "Validator ${validator_account_address} has been elected! Proceeding..."
      break
    else
      echo "Validator ${validator_account_address} has not been elected - waiting 30 seconds and checking again"
      sleep 30
    fi
  done

  echo "Current epos status is now:"
  ./hmy blockchain validator information $validator_account_address --node $node | jq '.result["epos-status"]'
}

trigger_double_signing() {
  echo "Triggering double-signing!"
  echo "Sending a double-signing messages every second for a total of ${double_signing_interval} second(s)"

  for i in $(seq 1 $double_signing_interval)
  do
    curl http://localhost:7777/trigger-next-double-sign #1> /dev/null 2>&1
    sleep 1
  done
  
  echo "Will check the validator status for up to 15 minutes (1+ epoch)..."
  for i in {0..15}
  do
    echo ""
    echo "Will wait 60 seconds and then retrieve the validator information for $validator_account_address"
    sleep 60
    
    validator_info=`./hmy blockchain validator information $validator_account_address --node $node`
    epos_status=`echo $validator_info | jq '.result["epos-status"]'`
    total_delegation_after_double_signing=`echo $validator_info | jq '.result["total-delegation"] | tonumber'`
    convert_wei_to_number "${total_delegation_after_double_signing}"
    total_delegation_after_double_signing=$converted
    
    echo ""
    echo "EPoS status for validator ${validator_account_address} is: ${epos_status}"
    echo "Total delegation to validator ${validator_account_address} after double-signing is: ${total_delegation_after_double_signing}"

    if (( total_delegation_after_double_signing < total_delegation_before_double_signing )); then
      break
    else
      echo "(please note that it might take a while for any eventual slashing to happen/to be detected)"
    fi

    echo ""
  done
  
  if (( total_delegation_after_double_signing < total_delegation_before_double_signing )); then
    difference=$((total_delegation_before_double_signing - total_delegation_after_double_signing))
    echo "Validator ${validator_account_address} and delegator ${delegator_account_address} were slashed a total of ${difference} tokens for double-signing!"
  else
    echo "It seems that the delegation amount wasn't slashed. Before double-signing: ${total_delegation_before_double_signing}, after double-signing: ${total_delegation_after_double_signing}"
  fi
}

cleanup() {
  # Cleanup tmux session - send CTRL+C to the node process, exit and press enter
  tmux send -t "${tmux_session_id}" C-c
  tmux send -t "${tmux_session_id}" "exit" Enter

  # Session should've already been cleared out - but just make sure it is
  tmux kill-session -t "${tmux_session_id}" 1> /dev/null 2>&1

  # Remove accounts
  ./hmy keys remove ${validator_account_name}
  ./hmy keys remove ${delegator_account_name}

  cd .. && rm -rf $node_id
}

convert_wei_to_number() {
  local wei="$1"
  converted=`printf '%.0f' $wei`
  converted=`echo $converted/1000000000000000000 | jq -nf /dev/stdin`
  converted=`printf "%.0f\n" "${converted}"`
}

setup() {
  initialize
  check_dependencies
  check_for_running_node

  install_node
  check_funding_account
  configure_double_signing
  start_node

  setup_accounts
  fund_accounts

  sync_node

  create_validator
  trigger_double_signing

  cleanup
}

if [ "$loop" = true ]; then
  # Run in an infinite loop
  while true; do
    setup
    if [ ! $? -eq 0 ]; then
      break
    fi
  done
else
  setup
fi
