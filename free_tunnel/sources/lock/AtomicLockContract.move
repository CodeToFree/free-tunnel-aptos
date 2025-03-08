module free_tunnel_aptos::atomic_lock {

    // =========================== Packages ===========================
    use std::event;
    use std::signer;
    use std::table;
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::primary_fungible_store;
    use std::timestamp::now_seconds;
    use free_tunnel_aptos::req_helpers::{Self, EXPIRE_PERIOD, EXPIRE_EXTRA_PERIOD};
    use free_tunnel_aptos::permissions;


    // =========================== Constants ==========================
    const EXECUTED_PLACEHOLDER: address = @0xed;
    const DEPLOYER: address = @free_tunnel_aptos;

    const ENOT_LOCK_MINT: u64 = 70;
    const EINVALID_REQ_ID: u64 = 71;
    const EINVALID_PROPOSER: u64 = 72;
    const EWAIT_UNTIL_EXPIRED: u64 = 73;
    const ENOT_BURN_UNLOCK: u64 = 74;
    const EINVALID_RECIPIENT: u64 = 75;
    const ENOT_DEPLOYER: u64 = 76;


    // ============================ Storage ===========================
    struct AtomicLockStorage has key, store {
        store_contract_signer_extend_ref: ExtendRef,
        proposedLock: table::Table<vector<u8>, address>,
        proposedUnlock: table::Table<vector<u8>, address>,
        lockedBalanceOf: table::Table<u8, u64>,
    }

    #[event]
    struct TokenLockProposed has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenLockExecuted has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenLockCancelled has drop, store {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenUnlockProposed has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenUnlockExecuted has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenUnlockCancelled has drop, store {
        reqId: vector<u8>,
        recipient: address,
    }

    fun init_module(admin: &signer) {
        let constructor_ref = object::create_named_object(admin, b"atomic_lock");
        let store_address_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let atomicLockStorage = AtomicLockStorage {
            store_contract_signer_extend_ref: extend_ref,
            proposedLock: table::new(),
            proposedUnlock: table::new(),
            lockedBalanceOf: table::new(),
        };
        move_to(&store_address_signer, atomicLockStorage);
    }


    // =========================== Functions ===========================
    #[view]
    public fun get_store_address(): address {
        object::create_object_address(&DEPLOYER, b"atomic_lock")
    }

    fun get_store_contract_signer(): signer acquires AtomicLockStorage {
        let storeA = borrow_global<AtomicLockStorage>(get_store_address());
        object::generate_signer_for_extending(&storeA.store_contract_signer_extend_ref)
    }

    public entry fun addToken(
        admin: &signer,
        tokenIndex: u8,
        tokenMetadata: Object<Metadata>,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::addTokenInternal(tokenIndex, tokenMetadata);
    }
    
    public entry fun removeTokenInternal(
        admin: &signer,
        tokenIndex: u8,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::removeTokenInternal(tokenIndex);
    }


    public entry fun proposeLock(
        _sender: &signer,
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        req_helpers::assertFromChainOnly(&reqId);
        req_helpers::checkCreatedTimeFrom(&reqId);
        let action = req_helpers::actionFrom(&reqId);
        assert!(action & 0x0f == 1, ENOT_LOCK_MINT);
        assert!(!table::contains(&storeA.proposedLock, reqId), EINVALID_REQ_ID);

        let proposerAddress = signer::address_of(proposer);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);
        table::add(&mut storeA.proposedLock, reqId, proposerAddress);

        let metadata = req_helpers::tokenMetadataFrom(&reqId);
        let assetToLock = primary_fungible_store::withdraw(proposer, metadata, amount);
        primary_fungible_store::deposit(get_store_address(), assetToLock);
        event::emit(TokenLockProposed{ reqId, proposer: proposerAddress });
    }
    

    public entry fun executeLock(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        let proposerAddress = *table::borrow(&storeA.proposedLock, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex,
        );

        *table::borrow_mut(&mut storeA.proposedLock, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        if (table::contains(&storeA.lockedBalanceOf, tokenIndex)) {
            let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
            *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount + amount;
        } else {
            table::add(&mut storeA.lockedBalanceOf, tokenIndex, amount);
        };
        event::emit(TokenLockExecuted{ reqId, proposer: proposerAddress });
    }


    public entry fun cancelLock(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        let proposerAddress = *table::borrow(&storeA.proposedLock, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_PERIOD(),
            EWAIT_UNTIL_EXPIRED,
        );
        table::remove(&mut storeA.proposedLock, reqId);

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        let metadata = req_helpers::tokenMetadataFrom(&reqId);
        let assetCancelled = primary_fungible_store::withdraw(&get_store_contract_signer(), metadata, amount);
        primary_fungible_store::deposit(proposerAddress, assetCancelled);
        event::emit(TokenLockCancelled{ reqId, proposer: proposerAddress });
    }


    public entry fun proposeUnlock(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertFromChainOnly(&reqId);
        req_helpers::checkCreatedTimeFrom(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        assert!(!table::contains(&storeA.proposedUnlock, reqId), EINVALID_REQ_ID);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_RECIPIENT);

        let amount = req_helpers::amountFrom(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom(&reqId);
        let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
        *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount - amount;
        table::add(&mut storeA.proposedUnlock, reqId, recipient);
        event::emit(TokenUnlockProposed{ reqId, recipient });
    }


    public entry fun executeUnlock(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        let recipient = *table::borrow(&storeA.proposedUnlock, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex,
        );

        *table::borrow_mut(&mut storeA.proposedUnlock, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom(&reqId);

        let metadata = req_helpers::tokenMetadataFrom(&reqId);
        let assetUnlocked = primary_fungible_store::withdraw(&get_store_contract_signer(), metadata, amount);
        primary_fungible_store::deposit(recipient, assetUnlocked);
        event::emit(TokenUnlockExecuted{ reqId, recipient });
    }


    public entry fun cancelUnlock(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(get_store_address());
        let recipient = *table::borrow(&storeA.proposedUnlock, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_EXTRA_PERIOD(),
            EWAIT_UNTIL_EXPIRED,
        );

        table::remove(&mut storeA.proposedUnlock, reqId);
        let amount = req_helpers::amountFrom(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom(&reqId);
        let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
        *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount + amount;
        event::emit(TokenUnlockCancelled{ reqId, recipient });
    }

}