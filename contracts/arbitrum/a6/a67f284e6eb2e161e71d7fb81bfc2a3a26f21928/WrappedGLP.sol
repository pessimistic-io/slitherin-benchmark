// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./ERC20WrapperUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20_IERC20Upgradeable.sol";
import "./IRewardRouterV2.sol";
import "./IGLPManager.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract WrappedGLPStorage {
    enum Contracts {
        GMXRewardRouterV2,
        GLPRewardRouterV2,
        Minter,
        RewardHandler
    }

    address public minter;
    address public rewardHandler;

    IRewardRouterV2 public gmxRewardRouterV2;
    IRewardRouterV2 public glpRewardRouterV2;
    IERC20Upgradeable public rewardToken;
}

contract WrappedGLP is Initializable, ERC20WrapperUpgradeable, OwnableUpgradeable, UUPSUpgradeable, WrappedGLPStorage {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address asset,
        address _rewardToken,
        string calldata _name,
        string calldata _symbol
    ) public initializer {
        __ERC20Wrapper_init(IERC20Upgradeable(asset));
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __UUPSUpgradeable_init();

        minter = msg.sender;
        rewardToken = IERC20Upgradeable(_rewardToken);

        gmxRewardRouterV2 = IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
        glpRewardRouterV2 = IRewardRouterV2(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "unauthorized");
        _;
    }

    modifier onlyRewardHandler() {
        require(msg.sender == rewardHandler, "unauthorized");
        _;
    }

    function setContract(Contracts c, address cAddress) external onlyOwner {
        require(cAddress != address(0));

        if (c == Contracts.GMXRewardRouterV2) {
            gmxRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }

        if (c == Contracts.GLPRewardRouterV2) {
            glpRewardRouterV2 = IRewardRouterV2(cAddress);
            return;
        }

        if (c == Contracts.Minter) {
            minter = cAddress;
            return;
        }

        if (c == Contracts.RewardHandler) {
            rewardHandler = cAddress;
            return;
        }
    }

    function depositFor(address account, uint256 amount) public override onlyMinter returns (bool result) {
        result = super.depositFor(account, amount);
    }

    function withdrawTo(address account, uint256 amount) public override onlyMinter returns (bool result) {
        result = super.withdrawTo(account, amount);
    }

    function recover(address account) public onlyOwner returns (uint256) {
        return _recover(account);
    }

    function claimRewards() public onlyRewardHandler {
        gmxRewardRouterV2.handleRewards(false, false, true, true, true, true, false);

        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (rewardBalance > 0) {
            SafeERC20Upgradeable.safeTransfer(rewardToken, msg.sender, rewardBalance);
        }
    }

    function getPrice() public view returns (uint256) {
        uint256 glpPrice = IGLPManager(glpRewardRouterV2.glpManager()).getPrice(true); // 1e30

        return glpPrice / 1e12; // 1e18
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

