// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.4;

import "./IStakingPool.sol";
import "./IApeXPool.sol";

contract StakingQuery {
    IStakingPool public lpPool;
    IApeXPool public apeXPool;

    constructor(address _lpPool, address _apeXPool) {
        lpPool = IStakingPool(_lpPool);
        apeXPool = IApeXPool(_apeXPool);
    }

    function getWithdrawableLPs(
        address user
    ) external view returns (uint256[] memory depositIds, uint256[] memory amounts) {
        uint256 length = lpPool.getDepositsLength(user);
        depositIds = new uint256[](length);
        uint256 count;
        IStakingPool.Deposit memory _deposit;
        for (uint256 i = 0; i < length; i++) {
            _deposit = lpPool.getDeposit(user, i);
            if (
                _deposit.amount > 0 &&
                (_deposit.lockFrom == 0 || block.timestamp > _deposit.lockFrom + _deposit.lockDuration)
            ) {
                depositIds[count] = i;
                count += 1;
            }
        }

        amounts = new uint256[](count);
        uint256 tempId;
        for (uint256 j = 0; j < count; j++) {
            tempId = depositIds[j];
            amounts[j] = lpPool.getDeposit(user, tempId).amount;
        }

        for (uint256 z = count; z < length; z++) {
            delete depositIds[z];
        }
    }

    function getWithdrawableAPEX(
        address user
    ) external view returns (uint256[] memory depositIds, uint256[] memory amounts) {
        uint256 length = apeXPool.getDepositsLength(user);
        depositIds = new uint256[](length);
        uint256 count;
        IApeXPool.Deposit memory _deposit;
        for (uint256 i = 0; i < length; i++) {
            _deposit = apeXPool.getDeposit(user, i);
            if (
                _deposit.amount > 0 &&
                (_deposit.lockFrom == 0 || block.timestamp > _deposit.lockFrom + _deposit.lockDuration)
            ) {
                depositIds[count] = i;
                count += 1;
            }
        }

        amounts = new uint256[](count);
        uint256 tempId;
        for (uint256 j = 0; j < count; j++) {
            tempId = depositIds[j];
            amounts[j] = apeXPool.getDeposit(user, tempId).amount;
        }

        for (uint256 z = count; z < length; z++) {
            delete depositIds[z];
        }
    }

    function getWithdrawableEsAPEX(
        address user
    ) external view returns (uint256[] memory depositIds, uint256[] memory amounts) {
        uint256 length = apeXPool.getEsDepositsLength(user);
        depositIds = new uint256[](length);
        uint256 count;
        IApeXPool.Deposit memory _deposit;
        for (uint256 i = 0; i < length; i++) {
            _deposit = apeXPool.getEsDeposit(user, i);
            if (
                _deposit.amount > 0 &&
                (_deposit.lockFrom == 0 || block.timestamp > _deposit.lockFrom + _deposit.lockDuration)
            ) {
                depositIds[count] = i;
                count += 1;
            }
        }

        amounts = new uint256[](count);
        uint256 tempId;
        for (uint256 j = 0; j < count; j++) {
            tempId = depositIds[j];
            amounts[j] = apeXPool.getEsDeposit(user, tempId).amount;
        }

        for (uint256 z = count; z < length; z++) {
            delete depositIds[z];
        }
    }

    function getWithdrawableYields(
        address user
    ) external view returns (uint256[] memory yieldIds, uint256[] memory amounts) {
        uint256 length = apeXPool.getYieldsLength(user);
        yieldIds = new uint256[](length);
        uint256 count;
        IApeXPool.Yield memory _yield;
        for (uint256 i = 0; i < length; i++) {
            _yield = apeXPool.getYield(user, i);
            if (_yield.amount > 0 && block.timestamp > _yield.lockUntil) {
                yieldIds[count] = i;
                count += 1;
            }
        }

        amounts = new uint256[](count);
        uint256 tempId;
        for (uint256 j = 0; j < count; j++) {
            tempId = yieldIds[j];
            amounts[j] = apeXPool.getYield(user, tempId).amount;
        }

        for (uint256 z = count; z < length; z++) {
            delete yieldIds[z];
        }
    }

    function getForceWithdrawYieldIds(address user) external view returns (uint256[] memory yieldIds) {
        uint256 length = apeXPool.getYieldsLength(user);
        yieldIds = new uint256[](length);
        uint256 count;
        IApeXPool.Yield memory _yield;
        for (uint256 i = 0; i < length; i++) {
            _yield = apeXPool.getYield(user, i);
            if (_yield.amount > 0) {
                yieldIds[count] = i;
                count += 1;
            }
        }

        for (uint256 z = count; z < length; z++) {
            delete yieldIds[z];
        }
    }
}

