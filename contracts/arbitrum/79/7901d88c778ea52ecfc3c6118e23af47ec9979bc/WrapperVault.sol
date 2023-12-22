// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ERC20Facet } from "./ERC20Facet.sol";
import { FactorGauge } from "./FactorGauge.sol";
import { IFactorGaugeController } from "./IFactorGaugeController.sol";

interface IFactorVault {
    function asset() external view returns (IERC20);

    function assetBalance() external view returns (uint);

    function getPricePerShare() external view returns (uint256);

    function deposit(uint256 assets, address owner) external;

    function withdraw(uint256 shares, address receiver, address owner) external;
}

contract WrapperVault is Initializable, ERC20Facet, OwnableUpgradeable, ReentrancyGuardUpgradeable, FactorGauge {
    using SafeERC20 for IERC20;

    IERC20 public underlyingAsset;
    IFactorVault public factorVault;

    error INSUFFICIENT_BALANCE();

    // Events
    event Deposited(address indexed from, address indexed to, uint256 amount);
    event Withdrawn(address indexed from, address indexed to, uint256 shares);
    event Staked(address indexed from, address indexed to, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _veFctr,
        address _gaugeController,
        address _factorVault
    ) public initializer {
        __ERC20_init(_name, _symbol, 18);
        __FactorGauge_init(_veFctr, _gaugeController);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        factorVault = IFactorVault(_factorVault);
        underlyingAsset = factorVault.asset();
    }

    function assetBalance() public view returns (uint) {
        return factorVault.assetBalance();
    }

    function asset() public view returns (IERC20) {
        return underlyingAsset;
    }

    function getPricePerShare() public view returns (uint256) {
        return factorVault.getPricePerShare();
    }

    function deposit(uint256 amount, address from) external nonReentrant {
        // Transfer underlying asset from user to this contract
        underlyingAsset.safeTransferFrom(from, address(this), amount);

        // Deposit the underlying asset to the FactorVault
        underlyingAsset.approve(address(factorVault), amount);
        uint256 beforeBalance = IERC20(address(factorVault)).balanceOf(address(this));
        factorVault.deposit(amount, address(this));
        uint256 afterBalance = IERC20(address(factorVault)).balanceOf(address(this));

        // Mint WrapperVault tokens to the user
        _mint(msg.sender, afterBalance - beforeBalance);
        emit Deposited(from, address(this), amount);
    }

    function withdraw(uint256 shares, address receiver, address owner) external nonReentrant {
        uint256 beforeBalance = IERC20(underlyingAsset).balanceOf(address(this));
        // Withdraw from the FactorVault to this contract
        factorVault.withdraw(shares, address(this), address(this));
        uint256 afterBalance = IERC20(underlyingAsset).balanceOf(address(this));
        // Burn WrapperVault tokens from the user
        _burn(owner, shares);

        // Transfer the underlying asset from this contract to the user
        underlyingAsset.safeTransfer(receiver, afterBalance - beforeBalance);
        emit Withdrawn(address(this), receiver, shares);
    }

    function stake(uint256 amount) external nonReentrant {
        // Transfer FactorVault tokens from user to this contract
        IERC20(address(factorVault)).safeTransferFrom(msg.sender, address(this), amount);

        // Mint WrapperVault tokens to the user (representing their stake)
        _mint(msg.sender, amount);
        emit Staked(msg.sender, address(this), amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (balanceOf(msg.sender) < amount) revert INSUFFICIENT_BALANCE();
        // Burn WrapperVault tokens from the user
        _burn(msg.sender, amount);

        // Transfer FactorVault tokens from this contract to user
        IERC20(address(factorVault)).safeTransfer(msg.sender, amount);
        emit Unstaked(address(this), msg.sender, amount);
    }

    /**
     * @notice redeems the user's reward
     * @return amount of reward token redeemed, in the same order as `getRewardTokens()`
     */
    function redeemRewards(address user) external nonReentrant returns (uint256[] memory) {
        return _redeemRewards(user);
    }

    /**
     * @notice returns the user's unclaimed reward
     * @return amount of unclaimed Fctr reward
     */
    function pendingRewards(address user) external view returns (uint256) {
        return _pendingRewards(user);
    }

    /// @notice returns the list of reward tokens
    function getRewardTokens() external view returns (address[] memory) {
        return _getRewardTokens();
    }

    /*/////////////////////////////////////////////////////
                    GAUGE - RELATED
    /////////////////////////////////////////////////////*/

    function _stakedBalance(address user) internal view override returns (uint256) {
        return balanceOf(user);
    }

    function _totalStaked() internal view override returns (uint256) {
        return totalSupply();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Facet, FactorGauge) {
        FactorGauge._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Facet, FactorGauge) {
        FactorGauge._afterTokenTransfer(from, to, amount);
    }
}

