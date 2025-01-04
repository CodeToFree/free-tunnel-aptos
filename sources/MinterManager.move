module free_tunnel_aptos::minter_manager {

    use std::signer;
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

    
    // =========================== Coin Admin Functions ===========================
    /**
     * Set up `TreasuryCapabilities` resource from `managed_coin::Capabilities`.
     *  This operation is irreversible!
     */
    public entry fun setupTreasuryFromCapabilities<CoinType>(coinAdmin: &signer) {
        let (burnCap, freezeCap, mintCap) = managed_coin::remove_caps<CoinType>(coinAdmin);
        move_to(coinAdmin, TreasuryCapManager<CoinType> {
            initialMintCap: mintCap,
            initialBurnCap: burnCap,
        });
        coin::destroy_freeze_cap(freezeCap);
    }

    /**
     * Fill the `MinterCap` resource with a `MintCapability` and a `BurnCapability`.
     *  Should be called only by the coin admin.
     */
    public entry fun issueMinterCap<CoinType>(coinAdmin: &signer, minterAddress: address) acquires TreasuryCapManager, MinterCap {
        let coinAdminAddress = signer::address_of(coinAdmin);
        assert!(exists<TreasuryCapManager<CoinType>>(coinAdminAddress), ENOT_SUPER_ADMIN);
        assert!(exists<MinterCap<CoinType>>(minterAddress), ENOT_REGISTERED);
        let minterCap = borrow_global_mut<MinterCap<CoinType>>(minterAddress);
        assert!(option::is_none(&minterCap.mintCapOpt), EALREADY_MINTER);
        assert!(option::is_none(&minterCap.burnCapOpt), EALREADY_MINTER);

        let TreasuryCapManager { 
            initialMintCap, initialBurnCap 
        } = borrow_global<TreasuryCapManager<CoinType>>(coinAdminAddress);
        let mintCap = *(copy initialMintCap);
        let burnCap = *(copy initialBurnCap);
        option::fill(&mut minterCap.mintCapOpt, mintCap);
        option::fill(&mut minterCap.burnCapOpt, burnCap);
    }

    /**
     * Revoke the `MinterCap` resource.
     *  Should be called by the super admin.
     */
    public entry fun revokeMinterCap<CoinType>(coinAdmin: &signer, minterAddress: address) acquires MinterCap {
        let coinAdminAddress = signer::address_of(coinAdmin);
        assert!(exists<TreasuryCapManager<CoinType>>(coinAdminAddress), ENOT_SUPER_ADMIN);
        assert!(exists<MinterCap<CoinType>>(minterAddress), ENOT_REGISTERED);

        let MinterCap<CoinType> { 
            mintCapOpt, burnCapOpt 
        } = move_from<MinterCap<CoinType>>(minterAddress);
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
    /**
     * Register a `MinterCap` resource for a minter. 
     *  Should be called by the minter itself.
     */
    public entry fun registerMinterCap<CoinType>(minter: &signer) {
        move_to(minter, MinterCap<CoinType> {
            mintCapOpt: option::none(),
            burnCapOpt: option::none(),
        });
    }

    /**
     * Extract the `MintCapability` and `BurnCapability` from the `MinterCap` resource.
     *  Should be called by a contract.
     */
    public fun extractCap<CoinType>(
        minter: &signer,
    ): (MintCapability<CoinType>, BurnCapability<CoinType>) acquires MinterCap {
        let minterCap = borrow_global_mut<MinterCap<CoinType>>(signer::address_of(minter));
        assert!(option::is_some(&minterCap.mintCapOpt), ENOT_MINTER);

        let mintCap = option::extract(&mut minterCap.mintCapOpt);
        let burnCap = option::extract(&mut minterCap.burnCapOpt);
        (mintCap, burnCap)
    }

    public entry fun mint<CoinType>(minter: &signer, to: address, amount: u64) acquires MinterCap {
        let minterCap = borrow_global<MinterCap<CoinType>>(signer::address_of(minter));
        assert!(option::is_some(&minterCap.mintCapOpt), ENOT_MINTER);

        let coinsToDeposit = coin::mint<CoinType>(
            amount, 
            option::borrow(&minterCap.mintCapOpt)
        );
        coin::deposit(to, coinsToDeposit);
    }

    public entry fun burn<CoinType>(minter: &signer, from: address, amount: u64) acquires MinterCap {
        let minterCap = borrow_global<MinterCap<CoinType>>(signer::address_of(minter));
        assert!(option::is_some(&minterCap.burnCapOpt), ENOT_MINTER);

        coin::burn_from<CoinType>(from, amount, option::borrow(&minterCap.burnCapOpt));
    }


    // =========================== View functions ===========================
    public fun isMinter<CoinType>(minterAddress: address): u8 acquires MinterCap {
        if (!exists<MinterCap<CoinType>>(minterAddress)) {
            0   // Not registered
        } else if (!option::is_some(&borrow_global<MinterCap<CoinType>>(minterAddress).mintCapOpt)) {
            1   // Registered, but not a minter
        } else if (!option::is_some(&borrow_global<MinterCap<CoinType>>(minterAddress).burnCapOpt)) {
            2   // Unreachable
        } else {
            3   // Is a minter
        }
    }


    // =========================== Test ===========================
    #[test_only]
    struct FakeMoney {}

    #[test(coinAdmin = @free_tunnel_aptos)]
    fun testIssueCoin(coinAdmin: &signer) {
        managed_coin::initialize<FakeMoney>(
            coinAdmin,
            b"FakeMoney",
            b"FM",
            18,      // decimal
            true     // monitor supply
        );
        aptos_framework::account::create_account_for_test(signer::address_of(coinAdmin));
        coin::register<FakeMoney>(coinAdmin);
    }

    #[test(coinAdmin = @free_tunnel_aptos)]
    public fun testSetupTreasury(coinAdmin: &signer) {
        testIssueCoin(coinAdmin);
        setupTreasuryFromCapabilities<FakeMoney>(coinAdmin);
    }

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee, to = @0x44cc)]
    fun testMint(coinAdmin: &signer, minter: &signer, to: &signer) acquires TreasuryCapManager, MinterCap {
        testSetupTreasury(coinAdmin);
        registerMinterCap<FakeMoney>(minter);
        issueMinterCap<FakeMoney>(coinAdmin, signer::address_of(minter));

        aptos_framework::account::create_account_for_test(signer::address_of(to));
        coin::register<FakeMoney>(to);
        mint<FakeMoney>(minter, signer::address_of(to), 1_000_000);
        burn<FakeMoney>(minter, signer::address_of(to), 1_000_000);
    }

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee, to = @0x44cc)]
    #[expected_failure]
    fun testMintFailure(coinAdmin: &signer, minter: &signer, to: &signer) acquires TreasuryCapManager, MinterCap {
        testMint(coinAdmin, minter, to);
        revokeMinterCap<FakeMoney>(coinAdmin, signer::address_of(minter));
        mint<FakeMoney>(minter, signer::address_of(to), 1_000_000);
    }

}