module free_tunnel_aptos::issue_coin {

    use std::option;
    use std::signer;
    use std::string::utf8;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, MintRef, BurnRef, Metadata};
    use aptos_framework::primary_fungible_store;

    const TOKEN_NAME: vector<u8> = b"Mock USD Circle";
    const TOKEN_SYMBOL: vector<u8> = b"MUSDC";
    const TOKEN_DECIMALS: u8 = 6;

    struct ManagerCap has key {
        mintRef: fungible_asset::MintRef,
        burnRef: fungible_asset::BurnRef,
    }

    fun init_module(sender: &signer) {
        let constructorRef = &object::create_named_object(sender, TOKEN_SYMBOL);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructorRef,
            option::none(),
            utf8(TOKEN_NAME), /* name */
            utf8(TOKEN_SYMBOL), /* symbol */
            TOKEN_DECIMALS, /* decimals */
            utf8(b"http://example.com/favicon.ico"), /* icon */
            utf8(b"http://example.com"), /* project */
        );

        let mintRef = fungible_asset::generate_mint_ref(constructorRef);
        let burnRef = fungible_asset::generate_burn_ref(constructorRef);

        move_to(sender, ManagerCap {
            mintRef,
            burnRef,
        });
    }
    
    public entry fun mint(sender: &signer, to: address,amount: u64) acquires ManagerCap {
        primary_fungible_store::mint(
            &borrow_global<ManagerCap>(signer::address_of(sender)).mintRef,
            to, amount
        );
    }

    #[view]
    public fun getMetadata(): Object<Metadata> {
        let assetAddress = object::create_object_address(&@free_tunnel_aptos, TOKEN_SYMBOL);
        object::address_to_object<Metadata>(assetAddress)
    }

    use std::debug;

    #[test(sender = @0x11)]
    public entry fun testMint(sender: &signer) acquires ManagerCap {
        init_module(sender);
        mint(sender, @0x12, 1_000_000);
        debug::print(&getMetadata());
    }


    // #[test(account = @0x1)]
    // public entry fun sender_can_set_message(account: signer) acquires MessageHolder {
    //     let _msg: string::String = string::utf8(b"Running test for sender_can_set_message...");

    //     let addr = signer::address_of(&account);
    //     aptos_framework::account::create_account_for_test(addr);
    //     set_message(account, string::utf8(b"Hello, Blockchain"));

    //     assert!(
    //         get_message(addr) == string::utf8(b"Hello, Blockchain"),
    //         ENO_MESSAGE
    //     );
    // }
}