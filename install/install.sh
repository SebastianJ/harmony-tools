#!/bin/bash

s3_url="s3://tools.harmony.one/release/linux-x86_64/harmony"
binaries=(harmony bootnode wallet hmy)

for binary in "${binaries[@]}"; do
  echo "Downloading ${binary} ..."
  rm -rf ${binary} && curl -LOs ${s3_url}/${binary} && chmod u+x ${binary}
done

echo "Downloading the latest node.sh from harmony-one/harmony (master) ..."
rm -rf node.sh && curl -LOs https://raw.githubusercontent.com/harmony-one/harmony/master/scripts/node.sh && chmod u+x node.sh

echo "Everything has now been downloaded."
echo "Make sure to start your node using -D to not overwrite your custom binaries!"
echo ""
