# Free Tunnel Aptos

A bridge protocol implementation on Aptos blockchain that enables cross-chain token transfers.

## Project Structure

The project consists of one main package, and maybe more packages in the future.

### 1. Free Tunnel Package (`/free_tunnel)

Core bridge protocol implementation with features:
- Atomic coin minting and burning
- Atomic coin locking and unlocking 
- Multi-signature executor validation
- Permission management for admin and proposers
- Support for multiple coin types

## Development

### Prerequisites

- [Aptos CLI](https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli)

### Build

```bash
cd free_tunnel
aptos move build
```

### Test

```bash
cd free_tunnel
aptos move test
```

### Project Structure
```
.
└── free_tunnel/
    └── sources/
        ├── Permissions.move
        ├── ReqHelpers.move
        ├── Utils.move
        ├── lock/
        │   └── AtomicLockContract.move
        └── mint/
            └── AtomicMintContract.move
```

### How to Deploy

1. Check `aptos` CLI version

```bash
aptos --version
# aptos 3.4.1
```

Remember to use `aptos 3.4.1` or `aptos 3.5.0` to deploy the contracts on Movement network.

2. Init and fund your account

```bash
cd mbtc
aptos init
# >>> choose `custom`
# >>> enter rpc: `https://full.testnet.movementinfra.xyz/v1` (for testnet) or `https://mainnet.movementnetwork.xyz/v1` (for mainnet)
# >>> enter faucet endpoint: `https://faucet.testnet.movementinfra.xyz/` (for testnet)
# >>> enter private key, or generate a new one
# record your account address
```

3. Build and deploy the MBTC contract

```bash
aptos move compile --dev
aptos move create-object-and-publish-package --address-name mbtc --named-addresses admin=<admin_address>
# record your published package object address
```

4. Build and deploy the Free Tunnel contract

Firstly repeat the step 2 to init your account in `free_tunnel` directory.

```bash
cd ..
cd free_tunnel
aptos init
```

Then build and deploy the contract. Due to the bug in `aptos v3.4.1` and `aptos v3.5.0`, you need to use the legacy way `move publish` to deploy the contract, instead of using `move create-object-and-publish-package`.

```bash
aptos move compile --dev
aptos move publish --named-addresses admin=<mbtc_admin_address>,mbtc=<mbtc_object_address>,free_tunnel_aptos=<free_tunnel_aptos_address>
```

5. Add minter/burner to whitelist

```bash
aptos move run --function-id <mbtc_package_address>::mbtc::add_minter --args address:<minter_address>
```
