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