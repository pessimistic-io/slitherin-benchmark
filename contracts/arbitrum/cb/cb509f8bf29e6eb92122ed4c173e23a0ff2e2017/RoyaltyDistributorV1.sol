// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IRoyaltyDistributorV1.sol";
import "./IWETH.sol";
import "./IOriginalMintersPool.sol";
import "./IEtherealSpheresPool.sol";

contract RoyaltyDistributorV1 is IRoyaltyDistributorV1, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant BASE_PERCENTAGE = 10000;
    uint256 public constant ORIGINAL_MINTERS_POOL_PERCENTAGE = 6667;

    address public weth;
    address public originalMintersPool;
    address public etherealSpheresPool;

    receive() external payable {
        if (msg.value > 0) {
            IWETH(weth).deposit{ value: msg.value }();
        }
    }

    function initialize(address weth_, address originalMintersPool_, address etherealSpheresPool_) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        weth = weth_;
        originalMintersPool = originalMintersPool_;
        etherealSpheresPool = etherealSpheresPool_;
        IERC20Upgradeable(weth_).safeApprove(originalMintersPool_, type(uint256).max);
        IERC20Upgradeable(weth_).safeApprove(etherealSpheresPool_, type(uint256).max);
    }

    function distribute() external {
        IERC20Upgradeable m_weth = IERC20Upgradeable(weth);
        uint256 balance = m_weth.balanceOf(address(this));
        if (balance > 0) {
            address m_originalMintersPool = originalMintersPool;
            uint256 originalMintersPoolShare = balance * ORIGINAL_MINTERS_POOL_PERCENTAGE / BASE_PERCENTAGE;
            m_weth.safeTransfer(m_originalMintersPool, originalMintersPoolShare);
            IOriginalMintersPool(m_originalMintersPool).provideReward(originalMintersPoolShare);
            address m_etherealSpheresPool = etherealSpheresPool;
            uint256 etherealSpheresPoolShare = balance - originalMintersPoolShare;
            m_weth.safeTransfer(m_etherealSpheresPool, etherealSpheresPoolShare);
            IEtherealSpheresPool(m_etherealSpheresPool).provideReward(etherealSpheresPoolShare);
            emit Distributed(originalMintersPoolShare, etherealSpheresPoolShare);
        }
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
