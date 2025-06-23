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

    struct AccessStorage has key, store {
        admin: address,
        minters: vector<address>,
        freezers: vector<address>,
        freeze_to_recipient: address,
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

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


    public entry fun transfer_admin(
        admin: &signer,
        new_admin: address
    ) acquires AccessStorage {
        assert!(signer::address_of(admin) == store().admin, ENOT_ADMIN);
        store_mut().admin = new_admin;
    }

    public entry fun add_minter(
        account: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(account) == store().admin, ENOT_ADMIN);
        vector::push_back(&mut store_mut().minters, minter_address);
    }

    public entry fun remove_minter(
        account: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(account) == store().admin, ENOT_ADMIN);
        vector::remove_value(&mut store_mut().minters, &minter_address);
    }

    public entry fun add_freezer(
        account: &signer,
        freezer_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(account) == store().admin, ENOT_ADMIN);
        vector::push_back(&mut store_mut().freezers, freezer_address);
    }


    // public entry fun mint(
    //     account: &signer,
    //     to: address,
    //     amount: u64
    // ) acquires AccessStorage {
    //     assert!(check_minter(signer::address_of(account)), ENOT_MINTER);
    //     primary_fungible_store::mint(&store().mint_ref, to, amount);
    // }

    // public entry fun burn(
    //     account: &signer,
    //     owner: address,
    //     amount: u64
    // ) acquires AccessStorage {
    //     assert!(check_minter(signer::address_of(account)), ENOT_MINTER);
    //     primary_fungible_store::burn(&store().burn_ref, owner, amount);
    // }

    // freeze users

    // unfreeze users

    // batch transfer

    // transfer to freeze_to_recipient
    
}
