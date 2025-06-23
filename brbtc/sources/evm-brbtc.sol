// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract brBTC is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    // @notice The address to which frozen users can transfer their tokens.
    address public freezeToRecipient;

    // @notice The addresses of the frozen users.
    mapping(address => bool) public frozenUsers;

    /**
     * ======================================================================================
     *
     * CONSTRUCTOR
     *
     * ======================================================================================
     */

    /**
     * @notice Disables the ability to call any additional initializer functions.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * ======================================================================================
     *
     * VIEW FUNCTIONS
     *
     * ======================================================================================
     */
    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

    /**
     * ======================================================================================
     *
     * ADMIN
     *
     * ======================================================================================
     */

    /**
     * @notice Initializes the contract with admin and token settings.
     * @param _defaultAdmin The default admin address (RBAC).
     * @param _minter The address of the brBTC minter.
     */
    function initialize(address _defaultAdmin, address _minter) public initializer {
        __ERC20_init("brBTC", "brBTC");
        __ERC20Burnable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(MINTER_ROLE, _minter);
    }

    /**
     * @notice set freezeToRecipient
     */
    function setFreezeToRecipient(address recipient) public onlyRole(DEFAULT_ADMIN_ROLE) {
        freezeToRecipient = recipient;
    }

    /**
     * ======================================================================================
     *
     * MINTER
     *
     * ======================================================================================
     */

    /**
     * @notice Mints brBTC to the specified address.
     * @param to The brBTC will be minted to this address.
     * @param amount The amount of brBTC to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burns brBTC.
     * @param amount The amount of brBTC to burn.
     */
    function burn(uint256 amount) public override {
        _burn(_msgSender(), amount);
    }

    /**
     * @notice Burns brBTC from the specified address.
     * @param account The address of the account to burn from.
     * @param amount The amount of brBTC to burn.
     */
    function burnFrom(address account, uint256 amount) public override {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    /**
     * ======================================================================================
     *
     * FREEZER
     *
     * ======================================================================================
     */

    /**
     * @notice Freezes the specified users.
     * @param users The addresses of the users to freeze.
     */
    function freezeUsers(address[] memory users) public onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < users.length; ++i) {
            frozenUsers[users[i]] = true;
        }
    }

    /**
     * @notice Unfreezes the specified users.
     * @param users The addresses of the users to unfreeze.
     */
    function unfreezeUsers(address[] memory users) public onlyRole(FREEZER_ROLE) {
        for (uint256 i = 0; i < users.length; ++i) {
            frozenUsers[users[i]] = false;
        }
    }

    /**
     * ======================================================================================
     *
     * USER INTERACTION
     *
     * ======================================================================================
     */

    /**
     * @notice Batch transfer amount to recipients.
     * @param recipients The addresses of the recipients.
     * @param amounts The amounts to transfer to the recipients.
     */
    function batchTransfer(address[] memory recipients, uint256[] memory amounts) public {
        require(recipients.length > 0, "USR001");
        require(recipients.length == amounts.length, "USR002");

        for (uint256 i = 0; i < recipients.length; ++i) {
            _transfer(_msgSender(), recipients[i], amounts[i]);
        }
    }

    /**
     * ======================================================================================
     *
     * OVERRIDE
     *
     * ======================================================================================
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (frozenUsers[sender]) {
            require(recipient == freezeToRecipient, "USR016");
        }
        super._transfer(sender, recipient, amount);
    }
}
