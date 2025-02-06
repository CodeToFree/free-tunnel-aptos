module free_tunnel_aptos::permissions {

    // =========================== Packages ===========================
    use std::aptos_hash;
    use std::event;
    use std::signer;
    use std::table;
    use std::vector;
    use std::timestamp::now_seconds;
    use free_tunnel_aptos::utils::{recoverEthAddress, smallU64ToString, smallU64Log10, assertEthAddressList, hexToString};
    use free_tunnel_aptos::req_helpers::{BRIDGE_CHANNEL, ETH_SIGN_HEADER};
    friend free_tunnel_aptos::atomic_mint;
    friend free_tunnel_aptos::atomic_lock;


    // =========================== Constants ==========================
    const ETH_ZERO_ADDRESS: vector<u8> = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    const ENOT_ADMIN: u64 = 20;
    const ENOT_PROPOSER: u64 = 21;
    const EALREADY_PROPOSER: u64 = 22;
    const ENOT_EXISTING_PROPOSER: u64 = 23;
    const EEXECUTORS_ALREADY_INITIALIZED: u64 = 24;
    const ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO: u64 = 25;
    const EARRAY_LENGTH_NOT_EQUAL: u64 = 26;
    const ENOT_MEET_THRESHOLD: u64 = 27;
    const EEXECUTORS_NOT_YET_ACTIVE: u64 = 28;
    const EEXECUTORS_OF_NEXT_INDEX_IS_ACTIVE: u64 = 29;
    const EDUPLICATED_EXECUTORS: u64 = 30;
    const ENON_EXECUTOR: u64 = 31;
    const ESIGNER_CANNOT_BE_EMPTY_ADDRESS: u64 = 32;
    const EINVALID_LENGTH: u64 = 33;
    const EINVALID_SIGNATURE: u64 = 34;
    const EACTIVE_SINCE_SHOULD_AFTER_36H: u64 = 35;
    const EACTIVE_SINCE_SHOULD_WITHIN_5D: u64 = 36;
    const EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS: u64 = 37;


    // ============================ Storage ===========================
    struct PermissionsStorage has key {
        _admin: address,
        _proposerIndex: table::Table<address, u64>,
        _proposerList: vector<address>,
        _executorsForIndex: vector<vector<vector<u8>>>,
        _exeThresholdForIndex: vector<u64>,
        _exeActiveSinceForIndex: vector<u64>,
    }

    fun init_module(admin: &signer) {
        initPermissionsStorage(admin);
    }

    public(friend) fun initPermissionsStorage(admin: &signer) {
        move_to(admin, PermissionsStorage {
            _admin: signer::address_of(admin),
            _proposerIndex: table::new(),
            _proposerList: vector::empty(),
            _executorsForIndex: vector::empty(),
            _exeThresholdForIndex: vector::empty(),
            _exeActiveSinceForIndex: vector::empty(),
        })
    }

    public entry fun initExecutors(
        sender: &signer,
        executors: vector<vector<u8>>,
        threshold: u64,
    ) acquires PermissionsStorage {
        assertOnlyAdmin(sender);
        initExecutorsInternal(executors, threshold);
    }

    #[event]
    struct AdminTransferred has drop, store {
        prevAdmin: address,
        newAdmin: address,
    }

    #[event]
    struct ProposerAdded has drop, store {
        proposer: address,
    }

    #[event]
    struct ProposerRemoved has drop, store {
        proposer: address,
    }

    #[event]
    struct ExecutorsUpdated has drop, store {
        executors: vector<vector<u8>>,
        threshold: u64,
        activeSince: u64,
        exeIndex: u64,
    }


    // =========================== Functions ===========================
    public(friend) fun assertOnlyAdmin(sender: &signer) acquires PermissionsStorage {
        let storeP = borrow_global<PermissionsStorage>(@free_tunnel_aptos);
        assert!(signer::address_of(sender) == storeP._admin, ENOT_ADMIN);
    }

    public(friend) fun assertOnlyProposer(sender: &signer) acquires PermissionsStorage {
        let storeP = borrow_global<PermissionsStorage>(@free_tunnel_aptos);
        assert!(storeP._proposerIndex.contains(signer::address_of(sender)), ENOT_PROPOSER);
    }

    public(friend) fun initAdminInternal(admin: address) acquires PermissionsStorage {
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        storeP._admin = admin;
        event::emit(AdminTransferred { prevAdmin: @0x0, newAdmin: admin });
    }

    public(friend) fun transferAdmin(sender: &signer, newAdmin: address) acquires PermissionsStorage {
        assertOnlyAdmin(sender);
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        let prevAdmin = storeP._admin;
        storeP._admin = newAdmin;
        event::emit(AdminTransferred { prevAdmin, newAdmin });
    }

    public entry fun addProposer(sender: &signer, proposer: address) acquires PermissionsStorage {
        assertOnlyAdmin(sender);
        addProposerInternal(proposer);
    }

    public(friend) fun addProposerInternal(proposer: address) acquires PermissionsStorage {
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        assert!(!storeP._proposerIndex.contains(proposer), EALREADY_PROPOSER);
        storeP._proposerList.push_back(proposer);
        storeP._proposerIndex.add(proposer, storeP._proposerList.length());
        event::emit(ProposerAdded { proposer });
    }

    public entry fun removeProposer(sender: &signer, proposer: address) acquires PermissionsStorage {
        assertOnlyAdmin(sender);
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        assert!(storeP._proposerIndex.contains(proposer), ENOT_EXISTING_PROPOSER);
        let index = storeP._proposerIndex.remove(proposer);
        let len = storeP._proposerList.length();
        if (index < len) {
            let lastProposer = storeP._proposerList[len - 1];
            storeP._proposerList[index - 1] = lastProposer;
            *storeP._proposerIndex.borrow_mut(lastProposer) = index;
        };
        storeP._proposerList.pop_back();
        event::emit(ProposerRemoved { proposer });
    }

    public(friend) fun initExecutorsInternal(executors: vector<vector<u8>>, threshold: u64) acquires PermissionsStorage {
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        assertEthAddressList(&executors);
        assert!(threshold <= executors.length(), ENOT_MEET_THRESHOLD);
        assert!(storeP._exeActiveSinceForIndex.length() == 0, EEXECUTORS_ALREADY_INITIALIZED);
        assert!(threshold > 0, ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO);
        checkExecutorsNotDuplicated(executors);
        storeP._executorsForIndex.push_back(executors);
        storeP._exeThresholdForIndex.push_back(threshold);
        storeP._exeActiveSinceForIndex.push_back(1);
        event::emit(ExecutorsUpdated { executors, threshold, activeSince: 1, exeIndex: 0 });
    }

    public entry fun updateExecutors(
        _sender: &signer,
        newExecutors: vector<vector<u8>>,
        threshold: u64,
        activeSince: u64,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires PermissionsStorage {
        assertEthAddressList(&newExecutors);
        assert!(threshold > 0, ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO);
        assert!(threshold <= newExecutors.length(), ENOT_MEET_THRESHOLD);
        assert!(
            activeSince > now_seconds() + 36 * 3600,  // 36 hours
            EACTIVE_SINCE_SHOULD_AFTER_36H,
        );
        assert!(
            activeSince < now_seconds() + 120 * 3600,  // 5 days
            EACTIVE_SINCE_SHOULD_WITHIN_5D,
        );
        checkExecutorsNotDuplicated(newExecutors);

        let msg = vector::empty<u8>();
        msg.append(ETH_SIGN_HEADER());
        msg.append(smallU64ToString(
            3 + BRIDGE_CHANNEL().length() + (29 + 43 * newExecutors.length()) 
            + (12 + smallU64Log10(threshold) + 1) + (15 + 10) + (25 + smallU64Log10(exeIndex) + 1)
        ));
        msg.append(b"[");
        msg.append(BRIDGE_CHANNEL());
        msg.append(b"]\n");
        msg.append(b"Sign to update executors to:\n");
        msg.append(joinAddressList(&newExecutors));
        msg.append(b"Threshold: ");
        msg.append(smallU64ToString(threshold));
        msg.append(b"\n");
        msg.append(b"Active since: ");
        msg.append(smallU64ToString(activeSince));
        msg.append(b"\n");
        msg.append(b"Current executors index: ");
        msg.append(smallU64ToString(exeIndex));

        checkMultiSignatures(msg, r, yParityAndS, executors, exeIndex);

        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        let newIndex = exeIndex + 1;
        if (newIndex == storeP._exeActiveSinceForIndex.length()) {
            storeP._executorsForIndex.push_back(newExecutors);
            storeP._exeThresholdForIndex.push_back(threshold);
            storeP._exeActiveSinceForIndex.push_back(activeSince);
        } else {
            assert!(
                activeSince >= storeP._exeActiveSinceForIndex[newIndex], 
                EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS
            );
            assert!(
                threshold >= storeP._exeThresholdForIndex[newIndex], 
                EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS
            );
            assert!(
                cmpAddrList(newExecutors, storeP._executorsForIndex[newIndex]), 
                EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS
            );
            storeP._executorsForIndex[newIndex] = newExecutors;
            storeP._exeThresholdForIndex[newIndex] = threshold;
            storeP._exeActiveSinceForIndex[newIndex] = activeSince;
        };
        event::emit(ExecutorsUpdated { executors: newExecutors, threshold, activeSince, exeIndex: newIndex });
    }


    fun joinAddressList(ethAddrs: &vector<vector<u8>>): vector<u8> {
        let result = vector::empty<u8>();
        let i = 0;
        while (i < ethAddrs.length()) {
            result.append(hexToString(&ethAddrs[i], true));
            result.append(b"\n");
            i = i + 1;
        };
        result
    }

    fun addressToU256(addr: vector<u8>): u256 {
        let value = 0;
        let i = 0;
        while (i < addr.length()) {
            value = value << 8;
            value = value + (addr[i] as u256);
            i = i + 1;
        };
        value
    }

    fun cmpAddrList(list1: vector<vector<u8>>, list2: vector<vector<u8>>): bool {
        if (list1.length() > list2.length()) {
            true
        } else if (list1.length() < list2.length()) {
            false
        } else {
            let i = 0;
            while (i < list1.length()) {
                let addr1U256 = addressToU256(list1[i]);
                let addr2U256 = addressToU256(list2[i]);
                if (addr1U256 > addr2U256) {
                    return true
                } else if (addr1U256 < addr2U256) {
                    return false
                };
                i = i + 1;
            };
            false
        }
    }

    public(friend) fun checkMultiSignatures(
        msg: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
    ) acquires PermissionsStorage {
        assert!(r.length() == yParityAndS.length(), EARRAY_LENGTH_NOT_EQUAL);
        assert!(r.length() == executors.length(), EARRAY_LENGTH_NOT_EQUAL);
        checkExecutorsForIndex(&executors, exeIndex);
        let i = 0;
        while (i < executors.length()) {
            checkSignature(msg, r[i], yParityAndS[i], executors[i]);
            i = i + 1;
        };
    }

    fun checkExecutorsNotDuplicated(executors: vector<vector<u8>>) {
        let i = 0;
        while (i < executors.length()) {
            let executor = executors[i];
            let j = 0;
            while (j < i) {
                assert!(executors[j] != executor, EDUPLICATED_EXECUTORS);
                j = j + 1;
            };
            i = i + 1;
        };
    }

    fun checkExecutorsForIndex(executors: &vector<vector<u8>>, exeIndex: u64) acquires PermissionsStorage {
        let storeP = borrow_global_mut<PermissionsStorage>(@free_tunnel_aptos);
        assertEthAddressList(executors);
        assert!(
            executors.length() >= storeP._exeThresholdForIndex[exeIndex], 
            ENOT_MEET_THRESHOLD
        );
        let activeSince = storeP._exeActiveSinceForIndex[exeIndex];
        assert!(activeSince < now_seconds(), EEXECUTORS_NOT_YET_ACTIVE);

        if (storeP._exeActiveSinceForIndex.length() > exeIndex + 1) {
            let nextActiveSince = storeP._exeActiveSinceForIndex[exeIndex + 1];
            assert!(nextActiveSince > now_seconds(), EEXECUTORS_OF_NEXT_INDEX_IS_ACTIVE);
        };

        let currentExecutors = storeP._executorsForIndex[exeIndex];
        let i = 0;
        while (i < executors.length()) {
            let executor = executors[i];
            let j = 0;
            while (j < i) {
                assert!(executors[j] != executor, EDUPLICATED_EXECUTORS);
                j = j + 1;
            };
            let isExecutor = false;
            let j = 0;
            while (j < currentExecutors.length()) {
                if (executor == currentExecutors[j]) {
                    isExecutor = true;
                    break
                };
                j = j + 1;
            };
            assert!(isExecutor, ENON_EXECUTOR);
            i = i + 1;
        };
    }

    fun checkSignature(msg: vector<u8>, r: vector<u8>, yParityAndS: vector<u8>, ethSigner: vector<u8>) {
        assert!(ethSigner != ETH_ZERO_ADDRESS, ESIGNER_CANNOT_BE_EMPTY_ADDRESS);
        assert!(r.length() == 32, EINVALID_LENGTH);
        assert!(yParityAndS.length() == 32, EINVALID_LENGTH);
        assert!(ethSigner.length() == 20, EINVALID_LENGTH);
        let digest = aptos_hash::keccak256(msg);
        let recoveredEthAddr = recoverEthAddress(digest, r, yParityAndS);
        assert!(recoveredEthAddr == ethSigner, EINVALID_SIGNATURE);
    }

    #[test]
    fun testJoinAddressList() {
        let addrs = vector[
            x"00112233445566778899aabbccddeeff00112233",
            x"000000000000000000000000000000000000beef"
        ];
        let result = joinAddressList(&addrs);
        let expected =
        b"0x00112233445566778899aabbccddeeff00112233\n0x000000000000000000000000000000000000beef\n";
        assert!(result == expected, 1);
        assert!(expected.length() == 43 * 2, 1);
    }

    #[test]
    fun testAddressToU256() {
        let addr = x"00112233445566778899aabbccddeeff00112233";
        let value = addressToU256(addr);
        assert!(value == 0x00112233445566778899aabbccddeeff00112233, 1);
    }

    #[test]
    fun testVectorCompare() {
        assert!(vector[1, 2, 3] == vector[1, 2, 3], 1);
        assert!(vector[1, 2, 3] != vector[1, 2, 4], 1);
    }

    #[test]
    fun testCmpAddrList() {
        let ethAddr1 = x"00112233445566778899aabbccddeeff00112233";
        let ethAddr2 = x"00112233445566778899aabbccddeeff00112234";
        let ethAddr3 = x"0000ffffffffffffffffffffffffffffffffffff";
        assert!(cmpAddrList(vector[ethAddr1, ethAddr2], vector[ethAddr1]), 1);
        assert!(!cmpAddrList(vector[ethAddr1], vector[ethAddr1, ethAddr2]), 1);
        assert!(cmpAddrList(vector[ethAddr1, ethAddr2], vector[ethAddr1, ethAddr1]), 1);
        assert!(!cmpAddrList(vector[ethAddr2, ethAddr1], vector[ethAddr2, ethAddr2]), 1);
        assert!(!cmpAddrList(vector[ethAddr2, ethAddr3], vector[ethAddr2, ethAddr3]), 1);
    }

}