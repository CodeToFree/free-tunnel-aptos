export ADMIN="0xb072a8901831f11fb096aa53bbcebc9d5bf7d503d1ac52c911db7a4bcf3c51e2"
export COIN_INFO="0x2fce3e0b57dc09fbb85d20b7e5c1af627332807f228a2b9400ee6879573a3e5d"
export COIN="$ADMIN::hello_rooch3::FSC"

rooch move publish

# test smallU64Log10 view function
rooch move run --function $ADMIN::utils::smallU64Log10 --args 10

# setupTreasuryCapManager
