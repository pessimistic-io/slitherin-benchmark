// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./extensions_IERC20MetadataUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./ILendingPool.sol";
import "./IStrategy.sol";
import "./GLPLeverageVaultStorage.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract GLPLeverageVault is
    Initializable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    GLPLeverageVaultStorage
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address sGLP_,
        address strategy_,
        string calldata _name,
        string calldata _symbol
    ) public initializer {
        __ERC4626_init(IERC20MetadataUpgradeable(sGLP_));
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        sGLP = IERC20Upgradeable(sGLP_);
        strategy = IStrategy(strategy_);
    }

    // ADMIN METHODS

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // PUBLIC METHODS

    function totalAssets() public view override returns (uint256) {
        return strategy.balanceOfEquity();
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        return strategy.previewWithdrawGLP(assets);
    }

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        if (assets == type(uint256).max) {
            assets = IERC20Upgradeable(asset()).balanceOf(msg.sender);
        }

        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        strategy.claimRewards();

        uint256 shares = previewDeposit(assets);
        require(shares > 0, "ERC4626: cannot mint 0 shares"); // We need to check for 0 since previewDeposit rounds down

        _deposit(_msgSender(), receiver, assets, shares);

        strategy.rebalance();

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        if (shares == type(uint256).max) {
            shares = maxRedeem(owner);
        }

        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        strategy.claimRewards();

        uint256 assets = _convertToAssets(shares, MathUpgradeable.Rounding.Down);
        require(assets > 0, "ERC4626: cannot redeem 0 assets"); // We need to check for 0 since previewRedeem rounds down

        assets = strategy.prepareWithdrawGLP(assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        strategy.claimRewards();

        uint256 assets = previewMint(shares);
        _deposit(_msgSender(), receiver, assets, shares);

        strategy.rebalance();

        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        strategy.claimRewards();

        if (assets == type(uint256).max) {
            assets = maxWithdraw(owner);
        }

        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

        uint256 shares = _convertToShares(assets, MathUpgradeable.Rounding.Up);

        assets = strategy.prepareWithdrawGLP(assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        SafeERC20Upgradeable.safeTransferFrom(sGLP, caller, address(this), assets);
        SafeERC20Upgradeable.safeApprove(sGLP, address(strategy), assets);
        strategy.deposit(assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Withdraw/redeem common workflow.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        strategy.withdrawTo(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

