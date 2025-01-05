module free_tunnel_rooch::atomic_mint {

    // =========================== Packages ===========================
    use std::option::{Self, Option};
    use moveos_std::account;
    use moveos_std::event;
    use moveos_std::signer;
    use moveos_std::table;
    use moveos_std::object::Object;
    use moveos_std::timestamp::now_seconds;
    
    use rooch_framework::account_coin_store;
    use rooch_framework::coin::CoinInfo;
    use rooch_framework::coin_store::{Self, CoinStore};

    use free_tunnel_rooch::req_helpers::{Self, EXPIRE_PERIOD, EXPIRE_EXTRA_PERIOD};
    use free_tunnel_rooch::permissions;
    use free_tunnel_rooch::minter_manager::{Self, MinterCap, TreasuryCapManager};


    // =========================== Constants ==========================
    const EXECUTED_PLACEHOLDER: address = @0xed;
    const DEPLOYER: address = @free_tunnel_rooch;

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

    struct StoreForCoinAndMinterCap<phantom CoinType: key + store> has key {
        burningCoins: Object<CoinStore<CoinType>>,
        minterCapOptObj: Option<Object<MinterCap<CoinType>>>,
    }

    #[event]
    struct TokenMintProposed has drop, copy {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenMintExecuted has drop, copy {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenMintCancelled has drop, copy {
        reqId: vector<u8>,
        recipient: address,
    }

    #[event]
    struct TokenBurnProposed has drop, copy {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenBurnExecuted has drop, copy {
        reqId: vector<u8>,
        proposer: address,
    }

    #[event]
    struct TokenBurnCancelled has drop, copy {
        reqId: vector<u8>,
        proposer: address,
    }

    fun init(admin: &signer) {
        let atomicMintGeneralStorage = AtomicMintGeneralStorage {
            proposedMint: table::new(),
            proposedBurn: table::new(),
        };
        account::move_resource_to(admin, atomicMintGeneralStorage);
    }


    // =========================== Functions ===========================
    public entry fun addToken<CoinType: key + store>(
        admin: &signer,
        tokenIndex: u8,
        coinInfoObj: &Object<CoinInfo<CoinType>>
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::addTokenInternal<CoinType>(tokenIndex, coinInfoObj);
        let storeForCoinAndMinterCap = StoreForCoinAndMinterCap<CoinType> {
            burningCoins: coin_store::create_coin_store<CoinType>(),
            minterCapOptObj: option::none(),
        };
        account::move_resource_to(admin, storeForCoinAndMinterCap);
    }


    public entry fun transferMinterCap<CoinType: key + store>(
        _minter: &signer,
        tokenIndex: u8,
        minterCapObj: Object<MinterCap<CoinType>>,
    ) {
        req_helpers::checkTokenType<CoinType>(tokenIndex);
        let storeForCoinAndMinterCap = 
            account::borrow_mut_resource<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);
        option::fill(&mut storeForCoinAndMinterCap.minterCapOptObj, minterCapObj);
    }


    public entry fun removeToken<CoinType: key + store>(
        admin: &signer,
        tokenIndex: u8,
    ) {
        permissions::assertOnlyAdmin(admin);
        req_helpers::removeTokenInternal(tokenIndex);
        let StoreForCoinAndMinterCap { burningCoins: burningCoinStoreObj, minterCapOptObj } = 
            account::move_resource_from<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);
        let burningCoins = coin_store::remove_coin_store<CoinType>(burningCoinStoreObj);
        account_coin_store::deposit(signer::address_of(admin), burningCoins);

        if (option::is_some(&minterCapOptObj)) {
            let minterCapObj = option::extract(&mut minterCapOptObj);
            minter_manager::destroyMinterCap(admin, minterCapObj);
        };
        option::destroy_none(minterCapOptObj);
    }


    public entry fun proposeMint<CoinType: key + store>(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 1, ENOT_LOCK_MINT);
        proposeMintPrivate<CoinType>(reqId, recipient);
    }


    public entry fun proposeMintFromBurn<CoinType: key + store>(
        proposer: &signer,
        reqId: vector<u8>,
        recipient: address,
    ) {
        permissions::assertOnlyProposer(proposer);
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeMintPrivate<CoinType>(reqId, recipient);
    }


    fun proposeMintPrivate<CoinType: key + store>(
        reqId: vector<u8>,
        recipient: address,
    ) {
        req_helpers::checkCreatedTimeFrom(&reqId);
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        assert!(table::contains(&storeA.proposedMint, reqId), EINVALID_REQ_ID);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_RECIPIENT);

        req_helpers::amountFrom<CoinType>(&reqId);
        req_helpers::tokenIndexFrom<CoinType>(&reqId);
        table::add(&mut storeA.proposedMint, reqId, recipient);

        event::emit(TokenMintProposed{ reqId, recipient });
    }


    public entry fun executeMint<CoinType: key + store>(
        sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        treasuryCapManagerObj: &mut Object<TreasuryCapManager<CoinType>>,
    ) {
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(&reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, 
        );

        *table::borrow_mut(&mut storeA.proposedMint, reqId) = EXECUTED_PLACEHOLDER;

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);

        let storeForCoinAndMinterCap = 
            account::borrow_mut_resource<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);
        let minterCapObj = option::borrow_mut(&mut storeForCoinAndMinterCap.minterCapOptObj);
        minter_manager::mint<CoinType>(
            sender, treasuryCapManagerObj, 
            minterCapObj, amount, recipient
        );
        event::emit(TokenMintExecuted{ reqId, recipient });
    }


    public entry fun cancelMint<CoinType: key + store>(
        _sender: &signer,
        reqId: vector<u8>,
    ) {
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        let recipient = *table::borrow(&storeA.proposedMint, reqId);
        assert!(recipient != EXECUTED_PLACEHOLDER, EINVALID_REQ_ID);
        assert!(
            now_seconds() > req_helpers::createdTimeFrom(&reqId) + EXPIRE_EXTRA_PERIOD(),
            EWAIT_UNTIL_EXPIRED
        );

        table::remove(&mut storeA.proposedMint, reqId);
        event::emit(TokenMintCancelled{ reqId, recipient });
    }


    public entry fun proposeBurn<CoinType: key + store>(
        proposer: &signer,
        reqId: vector<u8>,
    ) {
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        proposeBurnPrivate<CoinType>(proposer, reqId);
    }


    public entry fun proposeBurnForMint<CoinType: key + store>(
        proposer: &signer,
        reqId: vector<u8>,
    ) {
        req_helpers::assertToChainOnly(&reqId);
        assert!(req_helpers::actionFrom(&reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeBurnPrivate<CoinType>(proposer, reqId);
    }


    fun proposeBurnPrivate<CoinType: key + store>(
        proposer: &signer,
        reqId: vector<u8>,
    ) {
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        req_helpers::checkCreatedTimeFrom(&reqId);
        assert!(!table::contains(&storeA.proposedBurn, reqId), EINVALID_REQ_ID);

        let proposerAddress = signer::address_of(proposer);
        assert!(proposerAddress != EXECUTED_PLACEHOLDER, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom<CoinType>(&reqId);
        let _tokenIndex = req_helpers::tokenIndexFrom<CoinType>(&reqId);
        table::add(&mut storeA.proposedBurn, reqId, proposerAddress);
        
        let storeForCoinAndMinterCap = 
            account::borrow_mut_resource<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);
        let coinToBurn = account_coin_store::withdraw(proposer, amount);
        coin_store::deposit(&mut storeForCoinAndMinterCap.burningCoins, coinToBurn);
        event::emit(TokenBurnProposed{ reqId, proposer: proposerAddress });
    }


    public entry fun executeBurn<CoinType: key + store>(
        _sender: &signer,
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        treasuryCapManagerObj: &mut Object<TreasuryCapManager<CoinType>>,
    ) {
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        let storeForCoinAndMinterCap = account::borrow_mut_resource<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);

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
        let coinBurned = coin_store::withdraw(coinInside, amount);

        let minterCapObj = option::borrow_mut(&mut storeForCoinAndMinterCap.minterCapOptObj);
        minter_manager::burn<CoinType>(
            _sender, treasuryCapManagerObj, minterCapObj, coinBurned
        );
        event::emit(TokenBurnExecuted{ reqId, proposer: proposerAddress });
    }


    public entry fun cancelBurn<CoinType: key + store>(
        reqId: vector<u8>,
    ) {
        let storeA = account::borrow_mut_resource<AtomicMintGeneralStorage>(@free_tunnel_rooch);
        let storeForCoinAndMinterCap = account::borrow_mut_resource<StoreForCoinAndMinterCap<CoinType>>(@free_tunnel_rooch);

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
        let coinCancelled = coin_store::withdraw(coinInside, amount);

        account_coin_store::deposit(proposerAddress, coinCancelled);
        event::emit(TokenBurnCancelled{ reqId, proposer: proposerAddress });
    }

}