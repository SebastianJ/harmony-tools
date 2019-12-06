# pga.sh
Simple tool to check balances and perform automated transfers on Pangaea (or network of choice) using hmy.

## Installation:

```
curl -LO https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/pga/pga.sh && chmod u+x build.sh
./pga.sh --help
```

## Display all available options:
```
./pga.sh --help
```

```
Usage: ./pga.sh command [options]
Commands:
  transfer                    transfer tokens to provided addresses
  balances                    check balances for provided addresses
  verify-exact-balances       verify exact balances for provided addresses

Options:
  --addresses     addresses   a list of addresses, comma separated, e.g: one152yn6nvyjuln3kp4m2rljj6hvfapfhdxsmr79a,one1sefnsv9wa4xh3fffmr9f0mvfs7d09wjjnjucuy
  --file          path        the file to load wallet addresses from (preferred method)
  --export-file   path        the file to export data to (if the invoked method utilizes exports)
  --amount        amount      the amount to send to each address
  --api_endpoint  url         the API endpoint to use (defaults to https://api.s0.p.hmny.io)
  --help                      print this help section
```

## Check balances

### Using a file

```
./pga.sh balances --file check_wallets.txt
```

### Using a comma separated list

```
./pga.sh balances --addresses one1ljmsehr8sk80akt5fwswjv6y0rtu5awvtz6jle,one1ta2z8g0kt22pw5srtvuevjxnc8k6auac7ensxh,one19gnlttp3nduu584fxju2alzm58ex87r70ckfntone1kk5jdfrumaaryq3n25amplqd98thwxl9wkaj8m
```

## Check exact balances (and export the wallet addresses not matching the desired amount)

```
./pga.sh verify-exact-balances --file check_wallets.txt --amount 100000 --export-file invalid_wallet_balances.txt
```
