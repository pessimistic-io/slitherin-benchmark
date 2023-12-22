// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Address } from "./Address.sol";

import { IShareLocker } from "./IShareLocker.sol";
import { IBaseReward } from "./IBaseReward.sol";

contract ShareLocker is IShareLocker {
    using SafeERC20 for IERC20;
    using Address for address;

    address public override rewardPool;
    address public vault;
    address public creditManager;

    modifier onlyCreditManager() {
        require(creditManager == msg.sender, "ShareLocker: Caller is not the credit manager");
        _;
    }

    modifier onlyVault() {
        require(vault == msg.sender, "ShareLocker: Caller is not the vault");
        _;
    }

    constructor(
        address _vault,
        address _creditManager,
        address _rewardPool
    ) {
        require(_vault != address(0), "ShareLocker: _wethAddress cannot be 0x0");
        require(_creditManager != address(0), "ShareLocker: _wethAddress cannot be 0x0");
        require(_rewardPool != address(0), "ShareLocker: _wethAddress cannot be 0x0");
        
        require(_vault.isContract(), "ShareLocker:  _wethAddress is not a contract");
        require(_creditManager.isContract(), "ShareLocker:  _wethAddress is not a contract");
        require(_rewardPool.isContract(), "ShareLocker:  _wethAddress is not a contract");

        vault = _vault;
        creditManager = _creditManager;
        rewardPool = _rewardPool;
    }

    function stake(uint256 _amountIn) public override onlyVault {
        _claim();

        IBaseReward(rewardPool).stakeFor(address(this), _amountIn);
    }

    function withdraw(uint256 _amountOut) public override onlyVault {
        _claim();

        IBaseReward(rewardPool).withdraw(_amountOut);
    }

    function _claim() internal returns (uint256 claimed) {
        address rewardToken = IBaseReward(rewardPool).rewardToken();

        claimed = IBaseReward(rewardPool).claim(address(this));

        if (claimed > 0) {
            IERC20(rewardToken).transfer(creditManager, claimed);
        }
    }

    function harvest() external override onlyCreditManager returns (uint256) {
        return _claim();
    }

    function pendingRewards() public view returns (uint256) {
        return IBaseReward(rewardPool).pendingRewards(address(this));
    }
}

