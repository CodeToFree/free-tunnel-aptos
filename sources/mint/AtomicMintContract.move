module free_tunnel_aptos::atomic_mint {

    // =========================== Packages ===========================
    use std::event;
    use std::signer;
    use std::table;
    use std::option::{Self, Option};
    use std::timestamp::now_seconds;
    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};
    use free_tunnel_aptos::req_helpers::{Self, EXPIRE_PERIOD, EXPIRE_EXTRA_PERIOD};
    use free_tunnel_aptos::permissions;
    use free_tunnel_aptos::minter_manager;


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
    struct AtomicMintGeneralStorage has key {
        proposedMint: table::Table<vector<u8>, address>,
        proposedBurn: table::Table<vector<u8>, address>,
    }

    struct StoreForCoinAndMinterCap<phantom CoinType> has key {
        burningCoins: Coin<CoinType>,
        mintCapOpt: Option<MintCapability<CoinType>>,
        burnCapOpt: Option<BurnCapability<CoinType>>,
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
        let adminAddress = signer::address_of(admin);
        assert!(adminAddress == DEPLOYER, ENOT_DEPLOYER);
        
        permissions::initPermissionsStorage(admin);
        req_helpers::initReqHelpersStorage(admin);

        let atomicMintGeneralStorage = AtomicMintGeneralStorage {
            proposedMint: table::new(),
            proposedBurn: table::new(),
        };
        move_to(admin, atomicMintGeneralStorage);
    }


    // =========================== Functions ===========================
    public entry fun addToken<CoinType>(admin: &signer, tokenIndex: u8) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::addTokenInternal<CoinType>(tokenIndex);
        let storeForCoinAndMinterCap = StoreForCoinAndMinterCap<CoinType> {
            burningCoins: coin::zero<CoinType>(),
            mintCapOpt: option::none(),
            burnCapOpt: option::none(),
        };
        move_to(admin, storeForCoinAndMinterCap);
    }


    public entry fun transferMinterCap<CoinType>(
        minter: &signer,
        tokenIndex: u8,
    ) acquires StoreForCoinAndMinterCap {
        req_helpers::checkTokenType<CoinType>(tokenIndex);

        let (mintCap, burnCap) = minter_manager::extractCap<CoinType>(minter);
        let storeForCoinAndMinterCap = borrow_global_mut<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos);
        option::fill(&mut storeForCoinAndMinterCap.mintCapOpt, mintCap);
        option::fill(&mut storeForCoinAndMinterCap.burnCapOpt, burnCap);
    }


    public entry fun removeToken<CoinType>(
        admin: &signer,
        tokenIndex: u8,
    ) acquires StoreForCoinAndMinterCap {
        permissions::assertOnlyAdmin(admin);
        req_helpers::removeTokenInternal(tokenIndex);
        let StoreForCoinAndMinterCap { burningCoins, mintCapOpt, burnCapOpt } = move_from<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos);
        coin::deposit(signer::address_of(admin), burningCoins);

        if (option::is_some(&mintCapOpt)) {
            let mintCap = option::extract(&mut mintCapOpt);
            let burnCap = option::extract(&mut burnCapOpt);
            coin::destroy_mint_cap(mintCap);
            coin::destroy_burn_cap(burnCap);
        };
        option::destroy_none(mintCapOpt);
        option::destroy_none(burnCapOpt);
    }


    public entry fun proposeMint<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintGeneralStorage {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 1, ENOT_LOCK_MINT);
        proposeMintPrivate<CoinType>(reqId, recipient);
    }

    public entry fun proposeMintFromBurn<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintGeneralStorage {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeMintPrivate<CoinType>(reqId, recipient);
    }


    fun proposeMintPrivate<CoinType>(
        reqId: vector<u8>,
        recipient: address,
    ) acquires AtomicMintGeneralStorage {
        req_helpers::checkCreatedTimeFrom(&reqId);
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        assert!(table::contains(&storeA.proposedMint, reqId), EINVALID_REQ_ID);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_RECIPIENT);

        req_helpers::amountFrom<CoinType>(&reqId);
        req_helpers::tokenIndexFrom<CoinType>(&reqId);
        table::add(&mut storeA.proposedMint, reqId, recipient);

        event::emit(TokenMintProposed{ reqId, recipient });
    }


    public entry fun executeMint<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, 
        );

        *table::borrow_mut(&mut storeA.proposedMint, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        let mintCap = option::borrow(&borrow_global<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos).mintCapOpt);
        let coinsToDeposit = coin::mint<CoinType>(amount, mintCap);
        coin::deposit(recipient, coinsToDeposit);
        event::emit(TokenMintExecuted{ reqId, recipient });
    }


    public entry fun cancelMint<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintGeneralStorage {
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_EXTRA_PERIOD(),
            EWAIT_UNTIL_EXPIRED
        );

        table::remove(&mut storeA.proposedMint, reqId);
        event::emit(TokenMintCancelled{ reqId, recipient });
    }


    public entry fun proposeBurn<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        proposeBurnPrivate<CoinType>(proposer, reqId);
    }


    public entry fun proposeBurnForMint<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeBurnPrivate<CoinType>(proposer, reqId);
    }


    fun proposeBurnPrivate<CoinType>(
        proposer: &signer,
        reqId: vector<u8>,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        req_helpers::checkCreatedTimeFrom(&reqId);
        assert!(!table::contains(&storeA.proposedBurn, reqId), EINVALID_REQ_ID);

        let proposerAddress = signer::address_of(proposer);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        table::add(&mut storeA.proposedBurn, reqId, proposerAddress);
        
        let storeForCoinAndMinterCap = borrow_global_mut<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos);
        let coinToBurn = coin::withdraw<CoinType>(proposer, amount);
        coin::merge(&mut storeForCoinAndMinterCap.burningCoins, coinToBurn);
        event::emit(TokenBurnProposed{ reqId, proposer: proposerAddress });
    }


    public entry fun executeBurn<CoinType>(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        let storeForCoinAndMinterCap = borrow_global_mut<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos);

        let proposerAddress = *table::borrow(&storeA.proposedBurn, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, 
        );

        *table::borrow_mut(&mut storeA.proposedBurn, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        let coinInside = &mut storeForCoinAndMinterCap.burningCoins;
        let coinBurned = coin::extract(coinInside, amount);

        let burnCap = option::borrow(&storeForCoinAndMinterCap.burnCapOpt);
        coin::burn<CoinType>(coinBurned, burnCap);
        event::emit(TokenBurnExecuted{ reqId, proposer: proposerAddress });
    }


    public entry fun cancelBurn<CoinType>(
        reqId: vector<u8>,
    ) acquires AtomicMintGeneralStorage, StoreForCoinAndMinterCap {
        let storeA = borrow_global_mut<AtomicMintGeneralStorage>(@free_tunnel_aptos);
        let storeForCoinAndMinterCap = borrow_global_mut<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_aptos);

        let proposerAddress = *table::borrow(&storeA.proposedBurn, reqId);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_PERIOD(),
            EWAIT_UNTIL_EXPIRED
        );

        table::remove(&mut storeA.proposedBurn, reqId);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        let coinInside = &mut storeForCoinAndMinterCap.burningCoins;
        let coinCancelled = coin::extract(coinInside, amount);

        coin::deposit(proposerAddress, coinCancelled);
        event::emit(TokenBurnCancelled{ reqId, proposer: proposerAddress });
    }


    // =========================== Test ===========================
    #[test_only]
    use free_tunnel_aptos::minter_manager::FakeMoney;

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee)]
    fun testAddToken(coinAdmin: &signer, minter: &signer) acquires StoreForCoinAndMinterCap {
        // initialize
        init_module(coinAdmin);

        // setup TreasuryCapManager
        minter_manager::testSetupTreasury(coinAdmin);
        minter_manager::registerMinterCap<FakeMoney>(minter);
        minter_manager::issueMinterCap<FakeMoney>(coinAdmin, signer::address_of(minter));

        // add token
        addToken<FakeMoney>(coinAdmin, 15);
        transferMinterCap<FakeMoney>(minter, 15);
    }

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee)]
    fun testRemoveToken(coinAdmin: &signer, minter: &signer) acquires StoreForCoinAndMinterCap {
        testAddToken(coinAdmin, minter);
        removeToken<FakeMoney>(coinAdmin, 15);
    }

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee)]
    #[expected_failure]
    fun testAddTokenRepeatFailed(coinAdmin: &signer, minter: &signer) acquires StoreForCoinAndMinterCap {
        testAddToken(coinAdmin, minter);
        addToken<FakeMoney>(coinAdmin, 15);
    }

    #[test(coinAdmin = @free_tunnel_aptos, minter = @0x22ee)]
    #[expected_failure]
    fun testRemoveTokenRepeatFailed(coinAdmin: &signer, minter: &signer) acquires StoreForCoinAndMinterCap {
        testRemoveToken(coinAdmin, minter);
        removeToken<FakeMoney>(coinAdmin, 15);
    }

}