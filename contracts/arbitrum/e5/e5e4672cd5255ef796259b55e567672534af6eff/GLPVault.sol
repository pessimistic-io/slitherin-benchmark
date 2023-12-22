// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.17;

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
import "./IRewardRouterV2.sol";
import "./IRewardReader.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract GLPVault is Initializable, ERC4626Upgradeable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    // address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public WETH;
    IRewardRouterV2 public GMXRewardRouterV2;
    IRewardRouterV2 public GLPRewardRouterV2;

    uint public lastCompoundTimestamp;
    uint public minimumCompoundInterval;
    
    enum Contracts {
        GMXRewardRouterV2,
        GLPRewardRouterV2
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _asset, string memory _name, string memory _symbol, address _weth) initializer public {
        __ERC4626_init(IERC20MetadataUpgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();

        WETH = _weth;
        GMXRewardRouterV2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
        GLPRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

        minimumCompoundInterval = 2 days;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

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

    function setMinimumCompoundInterval(uint _seconds) external onlyOwner {
        minimumCompoundInterval = _seconds;
    }

    function shouldCompound() public view returns (bool) {
        return block.timestamp > (lastCompoundTimestamp + minimumCompoundInterval);

        // TODO: In future we may choose to determine compound frequency based on amount of claimable rewards
        // address[] memory _rewardTrackers = new address[](5);
        // _rewardTrackers[0] = GLPRewardRouterV2.stakedGmxTracker();
        // _rewardTrackers[1] = GLPRewardRouterV2.bonusGmxTracker();
        // _rewardTrackers[2] = GLPRewardRouterV2.feeGmxTracker();
        // _rewardTrackers[3] = GLPRewardRouterV2.stakedGlpTracker();
        // _rewardTrackers[4] = GLPRewardRouterV2.feeGlpTracker();

        // uint256[] memory stakingInfo = RewardReader.getStakingInfo(address(this), _rewardTrackers);
        // uint256 claimableEthRewards = ...;

        // return claimableEthRewards > (block.basefee * 10);
    }

    function compound() public nonReentrant whenNotPaused {
        require(owner() == _msgSender() || shouldCompound(), "Vault not ready for compounding.");

        lastCompoundTimestamp = block.timestamp;

        // Collect rewards and restake non-ETH rewards
        GMXRewardRouterV2.handleRewards(false, false, true, true, true, true, false);

        // Restake the ETH claimed
        uint256 balanceWETH = IERC20(WETH).balanceOf(address(this));
        if (balanceWETH > 0) {
            SafeERC20Upgradeable.safeApprove(IERC20Upgradeable(WETH), GLPRewardRouterV2.glpManager(), balanceWETH);
            GLPRewardRouterV2.mintAndStakeGlp(WETH, balanceWETH, 0, 0);
        }
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}

