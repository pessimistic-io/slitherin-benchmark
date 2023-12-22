// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { ERC20Upgradeable } from "./ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { UUPSUpgradeable } from "./UUPSUpgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IStrategy } from "./IStrategy.sol";

interface IStrategyUpgradeTo {
    function upgradeTo(address) external;
}

interface IFactorVaultManager {
    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool);
}

contract FactorVault is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using MathUpgradeable for uint256;

    // =============================================================
    //                          Events
    // =============================================================

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event NewProposedStrategy(address implementation);
    event UpgradeStrategy(address implementation);

    // =============================================================
    //                          Errors
    // =============================================================

    error INVALID_UPGRADE(); // 0xe07c0cab
    error INVALID_IMPLEMENTATION(); // 0xab9d37da
    error UPGRADE_NOT_READY(); // 0xc914c7d9
    error NOT_ENOUGH_SHARES(); // 0x5be4b761

    // =============================================================
    //                          Structs
    // =============================================================

    struct ProposedStrategy {
        address implementation;
        uint256 proposedTime;
    }

    // =============================================================
    //                   State Variables
    // =============================================================

    address public factorVaultManager;

    IStrategy public strategy;

    uint256 public upgradeTimelock;

    ProposedStrategy public proposedStrategy;

    // =============================================================
    //                      Functions
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        IStrategy _strategy,
        uint256 _upgradeTimelock
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        strategy = _strategy;
        upgradeTimelock = _upgradeTimelock;
        factorVaultManager = msg.sender;
    }

    function asset() public view returns (IERC20) {
        return IERC20(strategy.asset());
    }

    function assetBalance() public view returns (uint) {
        return asset().balanceOf(address(this)) + IStrategy(strategy).balanceOf();
    }

    function availableBalance() public view returns (uint256) {
        return asset().balanceOf(address(this));
    }

    function getPricePerShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (assetBalance() * 1e18) / totalSupply();
    }

    function deposit(uint256 amount, address receiver) public nonReentrant {
        strategy.beforeDeposit();
        uint256 _assetBalance = assetBalance();
        asset().safeTransferFrom(msg.sender, address(this), amount);
        earn();
        amount = assetBalance() - _assetBalance; // additional check for deflationary tokens
        uint256 shares = 0;

        if (totalSupply() == 0) {
            shares = amount;
        } else {
            shares = amount.mulDiv(totalSupply(), _assetBalance);
        }

        _deposit(msg.sender, receiver, amount, shares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    function earn() public {
        asset().safeTransfer(address(strategy), availableBalance());
        strategy.deposited();
    }

    function withdraw(uint256 shares, address receiver, address owner) public nonReentrant {
        if (shares > balanceOf(owner) || balanceOf(owner) == 0) revert NOT_ENOUGH_SHARES();

        uint256 amount = assetBalance().mulDiv(shares, totalSupply());

        uint256 balanceInVault = asset().balanceOf(address(this));

        // withdraw an asset balance in the vault and in the strategy
        if (balanceInVault < amount) {
            uint256 withdrawAmountFromStrategy = amount - balanceInVault;
            strategy.withdraw(withdrawAmountFromStrategy);
            uint256 _after = asset().balanceOf(address(this));
            uint256 _diff = _after - balanceInVault;
            if (_diff < withdrawAmountFromStrategy) {
                amount = balanceInVault + _diff;
            }
        }

        _withdraw(msg.sender, receiver, owner, amount, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        asset().safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    // propose new strategy
    function proposeStrategy(address newImplementation) public onlyOwner {
        proposedStrategy = ProposedStrategy({ implementation: newImplementation, proposedTime: block.timestamp });

        emit NewProposedStrategy(newImplementation);
    }

    // upgrade to new strategy
    function upgradeStrategy() public onlyOwner {
        if (proposedStrategy.implementation == address(0)) revert INVALID_IMPLEMENTATION();
        if (proposedStrategy.proposedTime + upgradeTimelock > block.timestamp) revert UPGRADE_NOT_READY();

        IStrategyUpgradeTo(address(strategy)).upgradeTo(proposedStrategy.implementation);
        proposedStrategy.implementation = address(0);
        proposedStrategy.proposedTime = 5000000000;

        earn();

        emit UpgradeStrategy(proposedStrategy.implementation);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // check if the new implementation is registered
        if (
            IFactorVaultManager(factorVaultManager).isRegisteredUpgrade(_getImplementation(), newImplementation) ==
            false
        ) revert INVALID_UPGRADE();
    }
}

