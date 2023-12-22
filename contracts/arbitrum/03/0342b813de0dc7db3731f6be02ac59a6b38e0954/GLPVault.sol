// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./IERC4626.sol";
import "./IERC20.sol";
import "./extensions_IERC20MetadataUpgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import { GLPVaultStorageV1 } from "./GLPVaultStorage.sol";
import "./IRewardRouterV2.sol";
import "./IRewardReader.sol";
import "./IGLPManager.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract GLPVault is
    Initializable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    GLPVaultStorageV1
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _asset,
        string calldata _name,
        string calldata _symbol,
        address _weth
    ) public initializer {
        require(_weth != address(0), "_weth is zero address");

        __ReentrancyGuard_init();
        __ERC4626_init(IERC20MetadataUpgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        WETH = _weth;
        GMXRewardRouterV2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
        GLPRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    }

    function initializeV2(string calldata _name, string calldata _symbol) public reinitializer(2) {
        __ERC20_init_unchained(_name, _symbol);
    }

    // ADMIN METHODS

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setContract(Contracts c, address cAddress) external onlyOwner {
        require(cAddress != address(0));

        if (c == Contracts.GMXRewardRouterV2) {
            GMXRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }

        if (c == Contracts.GLPRewardRouterV2) {
            GLPRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }
    }

    // PUBLIC METHODS

    function compound() public nonReentrant whenNotPaused {
        _compound();
    }

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        if (assets == type(uint256).max) {
            assets = IERC20Upgradeable(asset()).balanceOf(msg.sender);
        }

        require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

        _compound();

        uint256 shares = previewDeposit(assets);
        require(shares > 0, "ERC4626: cannot mint 0 shares"); // We need to check for 0 since previewDeposit rounds down

        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _compound();

        if (shares == type(uint256).max) {
            shares = maxRedeem(owner);
        }

        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        require(assets > 0, "ERC4626: cannot redeem 0 assets"); // We need to check for 0 since previewRedeem rounds down

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        _compound();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner) public override whenNotPaused returns (uint256) {
        _compound();

        if (assets == type(uint256).max) {
            assets = maxWithdraw(owner);
        }

        return super.withdraw(assets, receiver, owner);
    }

    // INTERNAL METHODS

    function _compound() internal {
        // Collect rewards and restake non-ETH rewards
        GMXRewardRouterV2.handleRewards(false, false, true, true, true, true, false);

        // Restake the ETH claimed
        uint256 balanceWETH = IERC20(WETH).balanceOf(address(this));
        if (balanceWETH > 0) {
            SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(WETH), GLPRewardRouterV2.glpManager(), balanceWETH);
            GLPRewardRouterV2.mintAndStakeGlp(WETH, balanceWETH, 0, 0);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}

