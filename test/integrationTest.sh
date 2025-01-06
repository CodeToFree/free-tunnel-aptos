export ADMIN="0xa057ec0bff69d3e9a761337f8d6d9a742e93be316ba3062747af2734c96f2c15" # address #1
export COIN_INFO="0x597f2b8b7bbc699436f7c1631f8188430e53b2f0ded6b7276f32896f3f4d1d6d"
export COIN="$ADMIN::hello_rooch3::FSC"

# 1. publish
rooch move publish

# 2. setupTreasuryCapManager
rooch move run --function $ADMIN::minter_manager::setupTreasuryCapManager \
    --args object_id:$COIN_INFO --type-args $COIN

# 2.1 return: TreasuryCapManager - 0x61707e7ffec111c1e3471d047bb9d08e82820844b158c00a64bb7f76ba686c16
export TREASURY_CAP_MANAGER="0x61707e7ffec111c1e3471d047bb9d08e82820844b158c00a64bb7f76ba686c16"

# 3. issueMinterCap
export MINTER="0xa1d54f2dbe95ccfd86181650e098d5bbbeb1ee12af16320745a51b87a8b4bfde"  # address #2
rooch move run --function $ADMIN::minter_manager::issueMinterCap \
    --args object_id:$TREASURY_CAP_MANAGER --args address:$MINTER --type-args $COIN

# 3.1 return: MinterCap - 0xf78d43ffed9bd10a0394663c1c4f08a5d8edf1851f230d85ad70d32c676a5501
export MINTER_CAP="0x57099c0499a32310c41b022f92d180fd1ef8994f72e716db3cee3f82bf7fcd30"

# 4. mint
export RECIPIENT="0xb072a8901831f11fb096aa53bbcebc9d5bf7d503d1ac52c911db7a4bcf3c51e2"
rooch account switch --address $MINTER
rooch move run --function $ADMIN::minter_manager::mint \
    --args object_id:$TREASURY_CAP_MANAGER --args object_id:$MINTER_CAP \
    --args 5000u256 --args address:$RECIPIENT \
    --type-args $COIN
rooch account balance --address $RECIPIENT

# 5. burn
rooch move run --function $ADMIN::minter_manager::mint \
    --args object_id:$TREASURY_CAP_MANAGER --args object_id:$MINTER_CAP \
    --args 5000u256 --args address:$MINTER \
    --type-args $COIN
rooch move run --function $ADMIN::minter_manager::burnFromSigner \
    --args object_id:$TREASURY_CAP_MANAGER --args object_id:$MINTER_CAP \
    --args 5000u256 --type-args $COIN
rooch account balance --address $MINTER

# 6. revokeMinterCap
rooch account switch --address $ADMIN
rooch move run --function $ADMIN::minter_manager::revokeMinterCap \
    --args object_id:$TREASURY_CAP_MANAGER --args object_id:$MINTER_CAP \
    --type-args $COIN

# 7. mint failed
rooch account switch --address $MINTER
rooch move run --function $ADMIN::minter_manager::mint \
    --args object_id:$TREASURY_CAP_MANAGER --args object_id:$MINTER_CAP \
    --args 5000u256 --args address:$MINTER \
    --type-args $COIN   # expected failure!

# 8. destroyTreasuryCapManager
## cannot destroy TreasuryCapManager, because it's a shared object
