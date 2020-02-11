# harmony-tools
Scripts and tools for Harmony.one

## install/install.sh
install.sh downloads the custom compiled static binaries from Amazon S3. It can also download the latest node.sh from harmony-one/harmony (master) using the flag --node

### Installation/Usage:


```
bash <(curl -sSL https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/install/install.sh) --node
```


## build/build.sh
build.sh is a custom build script that statically compiles the harmony, bootnode, wallet and hmy binaries using the master branches from harmony-one/harmony and harmony-one/go-sdk.

It also features support for uploading the binaries to Amazon S3.

### Installation:

```
curl -LOs https://raw.githubusercontent.com/SebastianJ/harmony-tools/master/build/build.sh && chmod u+x build.sh
./build.sh
```

This will compile all related harmony and go-sdk/hmy binaries and save them to ~/harmony by default. If you want to change the path where the binaries are copied use `--path YOUR_CUSTOM_PATH`.

You can proceed to copy all of the binaries to a separate directory or run the node from the build directory.

*IMPORTANT*:

If you're using node.sh in conjunction with this custom build you need to pass -D as a parameter to node.sh in order to stop it from downloading and overwriting the binaries, e.g:

```
./node.sh -k bls.key -N staking -z -D -S (or however you want to run, running as sudo or non-sudo etc)
```

### Display all available options:
```
./build.sh --help
```

```
Usage: ./build.sh [option] command
Options:
   --path                     path    the output path for compiled binaries
   --go-path                  path    the go path where git repositories should be cloned, will default to $HOME/go
   --gvm                              install go using gvm
   --go-version                       what version of golang to install, defaults to go1.12
   --harmony-branch           name    which git branch to use for the harmony, bls and mcl git repositories (defaults to master)
   --hmy-branch               name    which git branch to use for the go-sdk/hmy git repository (defaults to master)
   --help                             print this help section
```
