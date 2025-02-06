module free_tunnel_aptos::atomic_lock {

    // =========================== Packages ===========================
    use std::event;
    use std::signer;
    use std::table;
    use aptos_framework::coin::{Self, Coin};
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
        proposedLock: table::Table<vector<u8>, address>,
        proposedUnlock: table::Table<vector<u8>, address>,
        lockedBalanceOf: table::Table<u8, u64>,
    }

    struct CoinStorage<phantom CoinType> has key {
        lockedCoins: Coin<CoinType>,
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
        let atomicLockStorage = AtomicLockStorage {
            proposedLock: table::new(),
            proposedUnlock: table::new(),
            lockedBalanceOf: table::new(),
        };
        move_to(admin, atomicLockStorage);
    }


    // =========================== Functions ===========================
    public entry fun addToken<CoinType>(
        admin: &signer,
        tokenIndex: u8,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::addTokenInternal<CoinType>(tokenIndex);
        if (!exists<CoinStorage<CoinType>>(@free_tunnel_aptos)) {
            let coinStorage = CoinStorage<CoinType> {
                lockedCoins: coin::zero<CoinType>(),
            };
            move_to(admin, coinStorage);
        }
    }
    

    public entry fun removeToken<CoinType>(
        admin: &signer,
        tokenIndex: u8,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::removeTokenInternal(tokenIndex);
    }


    public entry fun proposeLock<CoinType>(
        _sender: &signer,
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage, CoinStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        req_helpers::assertFromChainOnly(&reqId);
        req_helpers::checkCreatedTimeFrom(&reqId);
        let action = req_helpers::actionFrom(&reqId);
        assert!(action & 0x0f == 1, ENOT_LOCK_MINT);
        assert!(!table::contains(&storeA.proposedLock, reqId), EINVALID_REQ_ID);

        let proposerAddress = signer::address_of(proposer);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        table::add(&mut storeA.proposedLock, reqId, proposerAddress);

        let coinStorage = borrow_global_mut<CoinStorage<CoinType>>(@free_tunnel_aptos);
        let coinToLock = coin::withdraw<CoinType>(proposer, amount);
        coin::merge(&mut coinStorage.lockedCoins, coinToLock);
        event::emit(TokenLockProposed{ reqId, proposer: proposerAddress });
    }
    

    public entry fun executeLock<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        let proposerAddress = *table::borrow(&storeA.proposedLock, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex,
        );

        *table::borrow_mut(&mut storeA.proposedLock, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        if (table::contains(&storeA.lockedBalanceOf, tokenIndex)) {
            let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
            *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount + amount;
        } else {
            table::add(&mut storeA.lockedBalanceOf, tokenIndex, amount);
        };
        event::emit(TokenLockExecuted{ reqId, proposer: proposerAddress });
    }


    public entry fun cancelLock<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage, CoinStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        let proposerAddress = *table::borrow(&storeA.proposedLock, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_PERIOD(),
            EWAIT_UNTIL_EXPIRED,
        );
        table::remove(&mut storeA.proposedLock, reqId);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        
        let coinStorage = borrow_global_mut<CoinStorage<CoinType>>(@free_tunnel_aptos);
        let coinInside = &mut coinStorage.lockedCoins;
        let coinCancelled = coin::extract(coinInside, amount);

        coin::deposit(proposerAddress, coinCancelled);
        event::emit(TokenLockCancelled{ reqId, proposer: proposerAddress });
    }


    public entry fun proposeUnlock<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertFromChainOnly(&reqId);
        req_helpers::checkCreatedTimeFrom(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        assert!(!table::contains(&storeA.proposedUnlock, reqId), EINVALID_REQ_ID);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_RECIPIENT);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
        *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount - amount;
        table::add(&mut storeA.proposedUnlock, reqId, recipient);
        event::emit(TokenUnlockProposed{ reqId, recipient });
    }


    public entry fun executeUnlock<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicLockStorage, CoinStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        let recipient = *table::borrow(&storeA.proposedUnlock, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex,
        );

        *table::borrow_mut(&mut storeA.proposedUnlock, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        let coinStorage = borrow_global_mut<CoinStorage<CoinType>>(@free_tunnel_aptos);
        let coinInside = &mut coinStorage.lockedCoins;
        let coinUnlocked = coin::extract(coinInside, amount);

        coin::deposit(recipient, coinUnlocked);
        event::emit(TokenUnlockExecuted{ reqId, recipient });
    }


    public entry fun cancelUnlock<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicLockStorage {
        let storeA = borrow_global_mut<AtomicLockStorage>(@free_tunnel_aptos);
        let recipient = *table::borrow(&storeA.proposedUnlock, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_EXTRA_PERIOD(),
            EWAIT_UNTIL_EXPIRED,
        );

        table::remove(&mut storeA.proposedUnlock, reqId);
        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        let originalAmount = *table::borrow(&storeA.lockedBalanceOf, tokenIndex);
        *table::borrow_mut(&mut storeA.lockedBalanceOf, tokenIndex) = originalAmount + amount;
        event::emit(TokenUnlockCancelled{ reqId, recipient });
    }

}