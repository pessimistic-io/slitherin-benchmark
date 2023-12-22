// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ITokenDistributor.sol";
import "./IMasterOfCoin.sol";

/**
 * @title  MagicTokenDistributor contract
 * @author Archethect
 * @notice This contract contains all functionalities to distribute $MAGIC tokens
 */
contract MagicTokenDistributor is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ITokenDistributor
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    bytes32 public constant STAKING_ROLE = keccak256("STAKING");

    IMasterOfCoin public magicDistributor;
    IERC20Upgradeable public magic;

    event MagicRewardPayout(address payee, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address magicDistributor_,
        address magic_,
        address admin_,
        address staking_
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        require(magicDistributor_ != address(0), "MAGICTOKENDISTRIBUTOR:ILLEGAL_ADDRESS");
        require(magic_ != address(0), "MAGICTOKENDISTRIBUTOR:ILLEGAL_ADDRESS");
        require(admin_ != address(0), "MAGICTOKENDISTRIBUTOR:ILLEGAL_ADDRESS");
        require(staking_ != address(0), "MAGICTOKENDISTRIBUTOR:ILLEGAL_ADDRESS");
        magicDistributor = IMasterOfCoin(magicDistributor_);
        magic = IERC20Upgradeable(magic_);
        _setupRole(ADMIN_ROLE, admin_);
        _setupRole(STAKING_ROLE, staking_);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(STAKING_ROLE, ADMIN_ROLE);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "MAGICTOKENDISTRIBUTOR:ACCESS_DENIED");
        _;
    }

    modifier onlyStaking() {
        require(hasRole(STAKING_ROLE, msg.sender), "MAGICTOKENDISTRIBUTOR:ACCESS_DENIED");
        _;
    }

    /**
     * @notice payout $MAGIC to address
     * @param payee receiver address of the $MAGIC
     * @param amount amount of $MAGIC to receive in Wei
     */
    function payout(address payee, uint256 amount) public nonReentrant onlyStaking {
        if (magic.balanceOf(address(this)) < amount) {
            require(
                magicDistributor.getPendingRewards(address(this)) + magic.balanceOf(address(this)) >= amount,
                "MAGICTOKENDISTRIBUTOR:INSUFFICIENT_FUNDS"
            );
            magicDistributor.requestRewards();
        }
        magic.safeTransfer(payee, amount);
        emit MagicRewardPayout(payee, amount);
    }

    /**
     * @notice withdraw $MAGIC tokens
     * @param amount amount of $MAGIC to withdraw in Wei
     * @param receiver receiver address of the $MAGIC
     */
    function withdrawFunds(uint256 amount, address receiver) public onlyAdmin {
        require(magic.balanceOf(address(this)) >= amount, "MAGICTOKENDISTRIBUTOR:INSUFFICIENT_FUNDS");
        magic.safeTransfer(receiver, amount);
    }

    /**
     * @notice get pending $MAGIC rewards
     */
    function getPendingRewards() public onlyAdmin {
        magicDistributor.requestRewards();
    }
}

