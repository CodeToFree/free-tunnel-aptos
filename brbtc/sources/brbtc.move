module brbtc::brbtc {

    use std::option;
    use std::vector;
    use std::signer;
    use std::object::{Self, Object};
    use std::fungible_asset::{Self, Metadata, MintRef, BurnRef, TransferRef};
    use std::primary_fungible_store;
    use std::string::utf8;

    const ASSET_SYMBOL: vector<u8> = b"brBTC";
    const ASSET_NAME: vector<u8> = b"brBTC";
    const ASSET_DECIMALS: u8 = 8;

    const ENOT_ADMIN: u64 = 200;
    const ENOT_MINTER: u64 = 201;
    const ENOT_FREEZER: u64 = 202;
    const EMISMATCH_LENGTH: u64 = 203;
    const EEMPTY_RECIPIENTS: u64 = 204;

    struct AccessStorage has key, store {
        admin: address,
        minters: vector<address>,
        freezers: vector<address>,
        freeze_to_recipient: address,
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    /**
     * ======================================================================================
     *
     * CONSTRUCTOR
     *
     * ======================================================================================
     */

    fun init_module(brbtc_object_deployer: &signer) {
        let constructor_ref = &object::create_named_object(brbtc_object_deployer, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME),
            utf8(ASSET_SYMBOL),
            ASSET_DECIMALS,
            utf8(b"https://etherscan.io/token/images/bedrockbrbtc_32.png"),
            utf8(b"https://app.bedrock.technology/brbtc"),
        );
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(&metadata_object_signer, AccessStorage {
            admin: @admin,
            minters: vector::empty(),
            freezers: vector::empty(),
            freeze_to_recipient: @admin,
            mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
            transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref),
        });
    }

    inline fun store(): &AccessStorage {
        borrow_global<AccessStorage>(@brbtc)
    }

    inline fun store_mut(): &mut AccessStorage {
        borrow_global_mut<AccessStorage>(@brbtc)
    }

    /**
     * ======================================================================================
     *
     * VIEW FUNCTIONS
     *
     * ======================================================================================
     */

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@brbtc, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    #[view]
    public fun get_admin(): address acquires AccessStorage {
        store().admin
    }

    #[view]
    public fun check_minter(account: address): bool acquires AccessStorage {
        vector::contains(&store().minters, &account)
    }

    #[view]
    public fun check_freezer(account: address): bool acquires AccessStorage {
        vector::contains(&store().freezers, &account)
    }

    #[view]
    public fun is_frozen(user: address): bool {
        primary_fungible_store::is_frozen(user, get_metadata())
    }

    /**
     * ======================================================================================
     *
     * ADMIN
     *
     * ======================================================================================
     */

    public entry fun transfer_admin(
        admin: &signer,
        new_admin: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        store_mut().admin = new_admin;
    }

    public entry fun add_minter(
        admin: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        vector::push_back(&mut store_mut().minters, minter_address);
    }

    public entry fun remove_minter(
        admin: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        vector::remove_value(&mut store_mut().minters, &minter_address);
    }

    public entry fun add_freezer(
        admin: &signer,
        freezer_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        vector::push_back(&mut store_mut().freezers, freezer_address);
    }

    public entry fun set_freeze_to_recipient(
        admin: &signer,
        freeze_to_recipient: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        store_mut().freeze_to_recipient = freeze_to_recipient;
    }

    /**
     * ======================================================================================
     *
     * MINTER
     *
     * ======================================================================================
     */

    public entry fun mint(
        minter: &signer,
        to: address,
        amount: u64
    ) acquires AccessStorage {
        assert!(check_minter(signer::address_of(minter)), ENOT_MINTER);
        primary_fungible_store::mint(&store().mint_ref, to, amount);
    }

    public entry fun burn(
        burner: &signer, // could be anyone
        amount: u64
    ) acquires AccessStorage {
        primary_fungible_store::burn(&store().burn_ref, signer::address_of(burner), amount);
    }

    /**
     * ======================================================================================
     *
     * FREEZER
     *
     * ======================================================================================
     */

    public entry fun freeze_users(
        freezer: &signer,
        users: vector<address>
    ) acquires AccessStorage {
        assert!(check_freezer(signer::address_of(freezer)), ENOT_FREEZER);
        let i = 0;
        while (i < vector::length(&users)) {
            primary_fungible_store::set_frozen_flag(&store().transfer_ref, *vector::borrow(&users, i), true);
            i = i + 1;
        }
    }

    public entry fun unfreeze_users(
        freezer: &signer,
        users: vector<address>
    ) acquires AccessStorage {
        assert!(check_freezer(signer::address_of(freezer)), ENOT_FREEZER);
        let i = 0;
        while (i < vector::length(&users)) {
            primary_fungible_store::set_frozen_flag(&store().transfer_ref, *vector::borrow(&users, i), false);
            i = i + 1;
        }
    }

    /**
     * ======================================================================================
     *
     * USER INTERACTION
     *
     * ======================================================================================
     */

    public entry fun batch_transfer(
        sender: &signer,
        recipients: vector<address>,
        amounts: vector<u64>
    ) {
        assert!(vector::length(&recipients) > 0, EEMPTY_RECIPIENTS);
        assert!(vector::length(&recipients) == vector::length(&amounts), EMISMATCH_LENGTH);
        let i = 0;
        while (i < vector::length(&recipients)) {
            primary_fungible_store::transfer(sender, get_metadata(), *vector::borrow(&recipients, i), *vector::borrow(&amounts, i));
            i = i + 1;
        }
    }

    public entry fun transfer_to_freeze_to_recipient(
        sender: &signer,
        amount: u64
    ) acquires AccessStorage {
        primary_fungible_store::transfer_with_ref(&store().transfer_ref, signer::address_of(sender), store().freeze_to_recipient, amount);
    }

}
