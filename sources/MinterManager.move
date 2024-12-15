module free_tunnel_aptos::minter_manager {

    use std::signer;
    use std::string::utf8;
    use std::option::{Self, Option};
    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::managed_coin;

    const ENOT_SUPER_ADMIN: u64 = 120;
    const ENOT_REGISTERED: u64 = 121;
    const EALREADY_MINTER: u64 = 122;
    const ENOT_MINTER: u64 = 123;

    struct TreasuryCapManager<phantom CoinType> has key {
        initialMintCap: MintCapability<CoinType>,
        initialBurnCap: BurnCapability<CoinType>,
    }

    struct MinterCap<phantom CoinType> has key {
        mintCapOpt: Option<MintCapability<CoinType>>,
        burnCapOpt: Option<BurnCapability<CoinType>>,
    }

    
    // =========================== Admin Functions ===========================
    /**
     * Set up `TreasuryCapabilities` resource from `coin::initialize`.
     */
    public entry fun setupTreasuryFromInitialize<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    ) {
        let (burnCap, freezeCap, mintCap) = coin::initialize<CoinType>(
            admin, utf8(name), utf8(symbol), decimals, true,
        );
        move_to(admin, TreasuryCapManager<CoinType> {
            initialMintCap: mintCap,
            initialBurnCap: burnCap,
        });
        coin::destroy_freeze_cap(freezeCap);
    }

    /**
     * Set up `TreasuryCapabilities` resource from `managed_coin::Capabilities`.
     *  This operation is irreversible!
     */
    public entry fun setupTreasuryFromCapabilities<CoinType>(admin: &signer) {
        let (burnCap, freezeCap, mintCap) = managed_coin::remove_caps<CoinType>(admin);
        move_to(admin, TreasuryCapManager<CoinType> {
            initialMintCap: mintCap,
            initialBurnCap: burnCap,
        });
        coin::destroy_freeze_cap(freezeCap);
    }

    /**
     * Register a `MinterCap` resource for a minter. 
     *  Should be called by the minter itself.
     */
    public entry fun registerMinterCap<CoinType>(minterSigner: &signer) {
        move_to(minterSigner, MinterCap<CoinType> {
            mintCapOpt: option::none(),
            burnCapOpt: option::none(),
        });
    }

    /**
     * Fill the `MinterCap` resource with a `MintCapability` and a `BurnCapability`.
     *  Should be called by the super admin.
     */
    public entry fun issueMinterCap<CoinType>(admin: &signer, minter: address) acquires TreasuryCapManager, MinterCap {
        let adminAddress = signer::address_of(admin);
        assert!(exists<TreasuryCapManager<CoinType>>(adminAddress), ENOT_SUPER_ADMIN);
        assert!(exists<MinterCap<CoinType>>(minter), ENOT_REGISTERED);
        let minterCap = borrow_global_mut<MinterCap<CoinType>>(minter);
        assert!(option::is_none(&minterCap.mintCapOpt), EALREADY_MINTER);
        assert!(option::is_none(&minterCap.burnCapOpt), EALREADY_MINTER);

        let TreasuryCapManager { 
            initialMintCap, initialBurnCap 
        } = borrow_global<TreasuryCapManager<CoinType>>(adminAddress);
        let mintCap = *(copy initialMintCap);
        let burnCap = *(copy initialBurnCap);
        option::fill(&mut minterCap.mintCapOpt, mintCap);
        option::fill(&mut minterCap.burnCapOpt, burnCap);
    }

    /**
     * Revoke the `MinterCap` resource.
     *  Should be called by the super admin.
     */
    public entry fun revokeMinterCap<CoinType>(admin: &signer, minter: address) acquires MinterCap {
        let adminAddress = signer::address_of(admin);
        assert!(exists<TreasuryCapManager<CoinType>>(adminAddress), ENOT_SUPER_ADMIN);
        assert!(exists<MinterCap<CoinType>>(minter), ENOT_REGISTERED);

        let MinterCap<CoinType> { 
            mintCapOpt, burnCapOpt 
        } = move_from<MinterCap<CoinType>>(minter);
        if (option::is_some(&mintCapOpt)) {
            coin::destroy_mint_cap(option::extract(&mut mintCapOpt));
        };
        if (option::is_some(&burnCapOpt)) {
            coin::destroy_burn_cap(option::extract(&mut burnCapOpt));
        };
        option::destroy_none(mintCapOpt);
        option::destroy_none(burnCapOpt);
    }


    // =========================== Minter Functions ===========================
    public entry fun mint<CoinType>(sender: &signer, to: address, amount: u64) acquires MinterCap {
        let minterCap = borrow_global<MinterCap<CoinType>>(signer::address_of(sender));
        assert!(option::is_some(&minterCap.mintCapOpt), ENOT_MINTER);

        let coinsToDeposit = coin::mint<CoinType>(
            amount, 
            option::borrow(&minterCap.mintCapOpt)
        );
        coin::deposit(to, coinsToDeposit);
    }

    public entry fun burn<CoinType>(sender: &signer, from: address, amount: u64) acquires MinterCap {
        let minterCap = borrow_global<MinterCap<CoinType>>(signer::address_of(sender));
        assert!(option::is_some(&minterCap.burnCapOpt), ENOT_MINTER);

        coin::burn_from<CoinType>(from, amount, option::borrow(&minterCap.burnCapOpt));
    }


    // =========================== Test ===========================
    #[test_only]
    struct FakeMoney {}

    #[test(admin = @0x33dd, minter = @0x22ee, to = @0x44cc)]
    public entry fun testMint(admin: &signer, minter: &signer, to: &signer) acquires TreasuryCapManager, MinterCap {
        managed_coin::initialize<FakeMoney>(admin, b"FakeMoney", b"FM", 18, true);
        setupTreasuryFromCapabilities<FakeMoney>(admin);
        registerMinterCap<FakeMoney>(minter);
        issueMinterCap<FakeMoney>(admin, signer::address_of(minter));

        let toAddress = signer::address_of(to);
        aptos_framework::account::create_account_for_test(toAddress);
        coin::register<FakeMoney>(to);
        mint<FakeMoney>(minter, signer::address_of(to), 1_000_000);
        burn<FakeMoney>(minter, signer::address_of(to), 1_000_000);
    }

    #[test(admin = @0x33dd, minter = @0x22ee, to = @0x44cc)]
    #[expected_failure]
    public entry fun testMintFailure(admin: &signer, minter: &signer, to: &signer) acquires TreasuryCapManager, MinterCap {
        managed_coin::initialize<FakeMoney>(admin, b"FakeMoney", b"FM", 18, true);
        setupTreasuryFromCapabilities<FakeMoney>(admin);
        registerMinterCap<FakeMoney>(minter);
        issueMinterCap<FakeMoney>(admin, signer::address_of(minter));
        revokeMinterCap<FakeMoney>(admin, signer::address_of(minter));

        let toAddress = signer::address_of(to);
        aptos_framework::account::create_account_for_test(toAddress);
        coin::register<FakeMoney>(to);
        mint<FakeMoney>(minter, signer::address_of(to), 1_000_000);
        burn<FakeMoney>(minter, signer::address_of(to), 1_000_000);
    }

}