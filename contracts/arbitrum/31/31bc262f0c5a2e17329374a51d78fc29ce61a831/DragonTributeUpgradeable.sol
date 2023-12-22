// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IERC20Mintable.sol";
import "./IDragonTribute.sol";

/**
 * @title DragonTribute
 * @author kvk0x
 *
 * The Dragon Depositor contract allows the transmutation of MAGIC into drMAGIC,
 * the wrapped MAGIC token representing exposure to the MDD ecosystem.
 *
 * This contract allows users to deposit MAGIC, for which they will be minted
 * drMAGIC at a predefined ratio.
 */
contract DragonTributeUpgradeable is
    IDragonTribute,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // ============================================ ROLES ==============================================

    /// @dev Contract owner. Allowed to update access to other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Role allowing the withdrawal of deposited MAGIC.
    bytes32 public constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");

    // ============================================ STATE ==============================================

    // ============= Global Immutable State ==============

    /// @notice MAGIC token
    /// @dev functionally immutable
    IERC20Upgradeable public magic;
    /// @notice drMAGIC token
    /// @dev functionally immutable
    IERC20Mintable public drMagic;

    // ============== Deposit Ratio State ================

    /// @notice The denominator for the expressed deposit ratio
    uint256 public constant RATIO_DENOM = 1e18;
    /// @notice The ratio of drMAGIC minted per MAGIC deposited. 1e18 represents a 1-1 ratio.
    ///         A mintRatio of 0 pauses the contract.
    uint256 public mintRatio;

    // ========================================== INITIALIZER ===========================================

    /**
     * @dev Prevents malicious initializations of base implementation by
     *      setting contract to initialized on deployment.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @param _magic                The MAGIC token address.
     * @param _drMagic              The drMAGIC token address.
     */
    function initialize(IERC20Upgradeable _magic, IERC20Mintable _drMagic) external initializer {
        require(address(_magic) != address(0), "Invalid magic token address");
        require(address(_drMagic) != address(0), "Invalid drMagic token address");

        __AccessControl_init();
        __ReentrancyGuard_init();

        _setupRole(ADMIN_ROLE, msg.sender);

        // Allow only admins to change other roles
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(WITHDRAW_ROLE, ADMIN_ROLE);

        magic = _magic;
        drMagic = _drMagic;

        mintRatio = 1e18;
    }

    // ======================================== USER OPERATIONS ========================================

    /**
     * @notice Deposit MAGIC to mint drMAGIC, according to the current mint ratio.
     *
     * @param _amount               The amount of MAGIC to deposit.
     */
    function deposit(uint256 _amount) external virtual override {
        _deposit(_amount, msg.sender);
    }

    /**
     * @notice Deposit MAGIC to mint drMAGIC, according to the current mint ratio.
     *         Can mint to another address besides depositor. Depositor must always
     *         directly provide MAGIC,
     *
     * @param _amount               The amount of MAGIC to deposit.
     * @param user                  The address to receive the minted drMAGIC.
     */
    function depositFor(uint256 _amount, address user) external virtual override {
        _deposit(_amount, user);
    }

    /**
     * @dev Internal function for deposit logic. Calculates the amount of drMAGIC to
     *      mint, collects the specified MAGIC, and mints the drMAGIc to the specified
     *      user.
     *
     * @param _amount               The amount of MAGIC to deposit.
     * @param user                  The address to receive the minted drMAGIC.
     */
    function _deposit(uint256 _amount, address user) internal nonReentrant {
        require(mintRatio > 0, "New deposits paused");
        require(_amount > 0, "Deposit amount 0");

        uint256 toMint = (_amount * mintRatio) / RATIO_DENOM;

        magic.safeTransferFrom(msg.sender, address(this), _amount);
        drMagic.mint(user, toMint);

        emit Deposit(user, _amount, toMint);
    }

    // ======================================= ADMIN OPERATIONS =======================================

    /**
     * @notice Withdraw deposited MAGIC. Any MAGIC withdrawn from this contract should be directed
     *         towards generating emissions for drMAGIC staking and other reward pools. The admin
     *         can defined the allowed withdrawers.
     *
     * @param _amount               The amount of MAGIC to withdraw.
     */
    function withdrawMagic(uint256 _amount, address to) external virtual override onlyRole(WITHDRAW_ROLE) {
        require(_amount > 0, "Withdraw amount 0");

        uint256 magicBal = magic.balanceOf(address(this));
        if (magicBal < _amount) _amount = magicBal;

        magic.safeTransfer(to, _amount);

        emit WithdrawMagic(msg.sender, to, _amount);
    }

    /**
     * @notice Change the ratio of units of drMAGIC minted per unit of MAGIC deposited. Can be used
     *         to encourage a certain drMAGIC/MAGIC peg or concentrate/dilute yield per unit of drMAGIC.
     *
     * @dev    The ratio has 18 units of precision, such that a value of 1e18 represents a 1-1 mint ratio.
     *
     * @param _ratio               The ratio of drMAGIC to mint per MAGIC deposited.
     */
    function setMintRatio(uint256 _ratio) external override onlyRole(ADMIN_ROLE) {
        mintRatio = _ratio;

        emit SetMintRatio(_ratio);
    }
}

