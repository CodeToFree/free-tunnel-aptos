export ADMIN="0x0af854fcad035f4134636ff2d7fa22591f8ff2f264f354ac04e53da06e318529"       # address #1
export COIN_ADMIN="0x3cf04c5602fbd9a8cb410174c3e46cf2c60d100431848d8f25375eef4f413480"  # address #2
export MINTER="0xef9201e82a49895312e4621ce73862700bdc8cc18b469906db712432808a6ae9"      # address #3
export COIN_INFO="0xf2cb370704a541d98778d5a4c0ae5c704489659aa9f872af79c03be5559538bf"
export COIN="$COIN_ADMIN::hello_rooch4::FSC"

# 1. publish
rooch account switch --address $ADMIN
rooch move publish

# 2. setupTreasuryCapManager
rooch account switch --address $COIN_ADMIN
rooch move run --function $ADMIN::minter_manager::setupTreasuryCapManager \
    --args object_id:$COIN_INFO --type-args $COIN

# 2.1 return: TreasuryCapManager - 0xd634c0255d5043a9061e213f75b66f81947ac9530419ff0691480154ba8ba6d0
export TREASURY_CAP_MANAGER="0xd634c0255d5043a9061e213f75b66f81947ac9530419ff0691480154ba8ba6d0"

# 3. issueMinterCap
rooch move run --function $ADMIN::minter_manager::issueMinterCap \
    --args object_id:$TREASURY_CAP_MANAGER --args address:$MINTER --type-args $COIN

# 3.1 return: MinterCap - 0xa7ec7b30cd2ec25333f2c2fb8e12a268139acd4f547fdbb43537794db74492a4
export MINTER_CAP="0xa7ec7b30cd2ec25333f2c2fb8e12a268139acd4f547fdbb43537794db74492a4"

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
rooch account switch --address $COIN_ADMIN
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
rooch account switch --address $COIN_ADMIN
rooch move run --function $ADMIN::minter_manager::destroyTreasuryCapManager \
    --args object_id:$TREASURY_CAP_MANAGER --type-args $COIN

# 9. add token
rooch account switch --address $ADMIN
rooch move run --function $ADMIN::atomic_mint::addToken \
    --args 36u8 --args 18u8 --type-args $COIN

# 10. transferMinterCap
rooch account switch --address $COIN_ADMIN
rooch move run --function $ADMIN::minter_manager::issueMinterCap \
    --args object_id:$TREASURY_CAP_MANAGER --args address:$COIN_ADMIN --type-args $COIN

export MINTER_CAP="0x8b9a8db1ddf9413bc4bea733b8bea324bb43848ae74e449dc9a0066bf0283708"
rooch move run --function $ADMIN::atomic_mint::transferMinterCap \
    --args 36u8 --args object_id:$MINTER_CAP --type-args $COIN

# 11. removeToken
rooch account switch --address $ADMIN
rooch move run --function $ADMIN::atomic_mint::removeToken --args 36u8 --type-args $COIN
