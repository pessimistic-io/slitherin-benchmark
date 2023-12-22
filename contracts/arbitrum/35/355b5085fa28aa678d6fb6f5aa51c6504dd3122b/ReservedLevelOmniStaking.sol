// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {IBurnableERC20} from "./IBurnableERC20.sol";
import "./LevelOmniStaking.sol";
import {ILevelNormalVesting} from "./ILevelNormalVesting.sol";

/**
 * @title MigrateableLevelOmniStaking
 * @notice Staking contract which lock an amount of LVL when preLVL vesting is in progress
 */
contract ReservedLevelOmniStaking is LevelOmniStaking {
    using SafeERC20 for IBurnableERC20;

    uint8 constant VERSION = 2;

    ILevelNormalVesting public normalVestingLVL;

    function reinit_setNormalVestingLVL(address _normalVestingLVL) external reinitializer(VERSION) {
        require(_normalVestingLVL != address(0), "Invalid address");
        normalVestingLVL = ILevelNormalVesting(_normalVestingLVL);
    }

    function unstake(address _to, uint256 _amount) external override whenNotPaused nonReentrant {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        address _sender = msg.sender;
        uint256 _reservedForVesting = 0;
        if (address(normalVestingLVL) != address(0)) {
            _reservedForVesting = normalVestingLVL.getReservedAmount(_sender);
        }
        require(_amount + _reservedForVesting <= stakedAmounts[_sender], "Insufficient staked amount");
        _updateCurrentEpoch();
        _updateUser(_sender, _amount, false);
        totalStaked -= _amount;
        stakeToken.safeTransfer(_to, _amount);
        emit Unstaked(_sender, _to, currentEpoch, _amount);
    }
}

