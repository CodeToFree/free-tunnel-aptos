module free_tunnel_aptos::atomic_mint {

    // =========================== Packages ===========================
    use std::event;
    use std::signer;
    use std::table;
    use std::timestamp::now_seconds;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::primary_fungible_store;
    use free_tunnel_aptos::req_helpers::{Self, EXPIRE_PERIOD, EXPIRE_EXTRA_PERIOD};
    use free_tunnel_aptos::permissions;
    use oft::oft_fa;


    // =========================== Constants ==========================
    const EXECUTED_PLACEHOLDER: address = @0xed;
    const DEPLOYER: address = @free_tunnel_aptos;

    const EINVALID_REQ_ID: u64 = 50;
    const EINVALID_RECIPIENT: u64 = 51;
    const ENOT_LOCK_MINT: u64 = 52;
    const ENOT_BURN_MINT: u64 = 53;
    const EWAIT_UNTIL_EXPIRED: u64 = 54;
    const EINVALID_PROPOSER: u64 = 55;
    const ENOT_BURN_UNLOCK: u64 = 56;
    const EALREADY_HAVE_MINTERCAP: u64 = 57;
    const ENOT_DEPLOYER: u64 = 58;


    // ============================ Storage ===========================
    struct AtomicMintStorage has key, store {
        store_contract_signer_extend_ref: ExtendRef,
        proposedMint: table::Table<vector<u8>, address>,
        proposedBurn: table::Table<vector<u8>, address>,
    }

    #[event]
    struct TokenMintProposed has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenMintExecuted has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenMintCancelled has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenBurnProposed has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenBurnExecuted has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenBurnCancelled has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    fun init_module(admin: &signer) {
        let constructor_ref = object::create_named_object(admin, b"atomic_mint");
        let store_address_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let atomicMintStorage = AtomicMintStorage {
            store_contract_signer_extend_ref: extend_ref,
            proposedMint: table::new(),
            proposedBurn: table::new(),
        };
        move_to(&store_address_signer, atomicMintStorage);
    }


    // =========================== Store Functions ===========================
    #[view]
    public fun get_store_address(): address {
        object::create_object_address(&DEPLOYER, b"atomic_mint")
    }

    fun get_store_contract_signer(): signer acquires AtomicMintStorage {
        let storeA = borrow_global<AtomicMintStorage>(get_store_address());
        object::generate_signer_for_extending(&storeA.store_contract_signer_extend_ref)
    }

    // =========================== Token Functions ===========================
    public entry fun addToken(
        admin: &signer, 
        tokenIndex: u8, 
        tokenMetadata: Object<Metadata>
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::addTokenInternal(tokenIndex, tokenMetadata);
    }

    public entry fun removeToken(
        admin: &signer,
        tokenIndex: u8,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::removeTokenInternal(tokenIndex);
    }


    // =========================== Mint/Burn Functions ===========================
    public entry fun proposeMint(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintStorage {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 1, ENOT_LOCK_MINT);
        proposeMintPrivate(reqId, recipient);
    }

    public entry fun proposeMintFromBurn(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintStorage {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeMintPrivate(reqId, recipient);
    }


    fun proposeMintPrivate(
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintStorage {
        req_helpers::checkCreatedTimeFrom(&reqId);
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());
        assert!(!table::contains(&storeA.proposedMint, reqId), EINVALID_REQ_ID);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_RECIPIENT);

        req_helpers::amountFrom(&reqId);
        req_helpers::tokenIndexFrom(&reqId);
        table::add(&mut storeA.proposedMint, reqId, recipient);

        event::emit(TokenMintProposed{ reqId, recipient });
    }


    public entry fun executeMint(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicMintStorage {
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, 
        );

        *table::borrow_mut(&mut storeA.proposedMint, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        let contract_signer = get_store_contract_signer();
        oft_fa::mint(&contract_signer, recipient, amount);

        event::emit(TokenMintExecuted{ reqId, recipient });
    }


    public entry fun cancelMint(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintStorage {
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_EXTRA_PERIOD(),
            EWAIT_UNTIL_EXPIRED
        );

        table::remove(&mut storeA.proposedMint, reqId);
        event::emit(TokenMintCancelled{ reqId, recipient });
    }


    public entry fun proposeBurn(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintStorage {
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        proposeBurnPrivate(proposer, reqId);
    }


    public entry fun proposeBurnForMint(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintStorage {
        req_helpers::assertFromChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeBurnPrivate(proposer, reqId);
    }


    fun proposeBurnPrivate(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintStorage {
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());
        req_helpers::checkCreatedTimeFrom(&reqId);
        assert!(!table::contains(&storeA.proposedBurn, reqId), EINVALID_REQ_ID);

        let proposerAddress = signer::address_of(proposer);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);
        table::add(&mut storeA.proposedBurn, reqId, proposerAddress);

        let metadata = req_helpers::tokenMetadataFrom(&reqId);
        let assetToBurn = primary_fungible_store::withdraw(proposer, metadata, amount);
        primary_fungible_store::deposit(get_store_address(), assetToBurn);
        event::emit(TokenBurnProposed{ reqId, proposer: proposerAddress });
    }


    public entry fun executeBurn(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicMintStorage {
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());

        let proposerAddress = *table::borrow(&storeA.proposedBurn, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, 
        );

        *table::borrow_mut(&mut storeA.proposedBurn, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        let contract_signer = get_store_contract_signer();
        oft_fa::burn(&contract_signer, get_store_address(), amount);

        event::emit(TokenBurnExecuted{ reqId, proposer: proposerAddress });
    }


    public entry fun cancelBurn(
        reqId: vector<u8>,
    ) acquires AtomicMintStorage {
        let storeA = borrow_global_mut<AtomicMintStorage>(get_store_address());

        let proposerAddress = *table::borrow(&storeA.proposedBurn, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_PERIOD(),
            EWAIT_UNTIL_EXPIRED
        );

        table::remove(&mut storeA.proposedBurn, reqId);

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        let metadata = req_helpers::tokenMetadataFrom(&reqId);
        let assetCancelled = primary_fungible_store::withdraw(&get_store_contract_signer(), metadata, amount);
        primary_fungible_store::deposit(proposerAddress, assetCancelled);

        event::emit(TokenBurnCancelled{ reqId, proposer: proposerAddress });
    }

}