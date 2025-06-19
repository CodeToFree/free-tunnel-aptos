module mbtc::mbtc {

    use std::option;
    use std::vector;
    use std::signer;
    use std::object::{Self, Object};
    use std::fungible_asset::{Self, BurnRef, Metadata, MintRef};
    use std::primary_fungible_store;
    use std::string::utf8;

    const ASSET_SYMBOL: vector<u8> = b"M-BTC";
    const ASSET_NAME: vector<u8> = b"Merlin's Seal BTC";
    const ASSET_DECIMALS: u8 = 8;

    const ENOT_ADMIN: u64 = 200;
    const ENOT_MINTER: u64 = 201;

    struct AccessStorage has key, store {
        admin: address,
        minters: vector<address>,
        mint_ref: MintRef,
        burn_ref: BurnRef,
    }

    fun init_module(mbtc_object_deployer: &signer) {
        let constructor_ref = &object::create_named_object(mbtc_object_deployer, ASSET_SYMBOL);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(ASSET_NAME),
            utf8(ASSET_SYMBOL),
            ASSET_DECIMALS,
            utf8(b"https://pubic-storage.merlinchain.io/icons/MBTC.png"),
            utf8(b"https://merlinchain.io/"),
        );
        let metadata_object_signer = object::generate_signer(constructor_ref);
        move_to(&metadata_object_signer, AccessStorage {
            admin: @admin,
            minters: vector::empty(),
            mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
        });
    }

    #[view]
    /// Return the address of the managed fungible asset that's created when this module is deployed.
    public fun get_metadata(): Object<Metadata> {
        let asset_address = object::create_object_address(&@mbtc, ASSET_SYMBOL);
        object::address_to_object<Metadata>(asset_address)
    }

    inline fun store(): &AccessStorage {
        let asset_address = object::create_object_address(&@mbtc, ASSET_SYMBOL);
        borrow_global<AccessStorage>(asset_address)
    }

    public entry fun transfer_admin(
        admin: &signer,
        new_admin: address
    ) acquires AccessStorage {
        let store_mut = borrow_global_mut<AccessStorage>(@mbtc);
        assert!(signer::address_of(admin) == store_mut.admin, ENOT_ADMIN);
        store_mut.admin = new_admin;
    }

    #[view]
    public fun get_admin(): address acquires AccessStorage {
        store().admin
    }

    public entry fun add_minter(
        account: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(account) == store().admin, ENOT_ADMIN);
        let asset_address = object::create_object_address(&@mbtc, ASSET_SYMBOL);
        let store_mut = borrow_global_mut<AccessStorage>(asset_address);
        vector::push_back(&mut store_mut.minters, minter_address);
    }

    public entry fun remove_minter(
        account: &signer,
        minter_address: address
    ) acquires AccessStorage {
        assert!(signer::address_of(account) == store().admin, ENOT_ADMIN);
        let asset_address = object::create_object_address(&@mbtc, ASSET_SYMBOL);
        let store_mut = borrow_global_mut<AccessStorage>(asset_address);
        vector::remove_value(&mut store_mut.minters, &minter_address);
    }

    #[view]
    public fun check_minter(account: address): bool acquires AccessStorage {
        vector::contains(&store().minters, &account)
    }

    public entry fun mint(
        account: &signer,
        to: address,
        amount: u64
    ) acquires AccessStorage {
        assert!(check_minter(signer::address_of(account)), ENOT_MINTER);
        primary_fungible_store::mint(&store().mint_ref, to, amount);
    }

    public entry fun burn(
        account: &signer,
        owner: address,
        amount: u64
    ) acquires AccessStorage {
        assert!(check_minter(signer::address_of(account)), ENOT_MINTER);
        primary_fungible_store::burn(&store().burn_ref, owner, amount);
    }
}
