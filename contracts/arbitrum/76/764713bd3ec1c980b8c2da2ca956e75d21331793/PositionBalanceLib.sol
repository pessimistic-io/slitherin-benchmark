// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ProxyCallerApi.sol";
import "./PositionInfo.sol";
import "./IPoolAdapter.sol";
import "./IMinimaxMain.sol";

library PositionBalanceLib {
    using ProxyCallerApi for ProxyCaller;

    struct PositionBalanceV3 {
        uint gasTank;
        uint stakedAmount;
        uint poolStakedAmount;
        uint[] poolRewardAmounts;
    }

    struct PositionBalanceV2 {
        uint gasTank;
        uint stakedAmount;
        uint poolStakedAmount;
        uint poolRewardAmount;
    }

    struct PositionBalanceV1 {
        uint total;
        uint reward;
        uint gasTank;
    }

    function getManyV3(
        IMinimaxMain main,
        mapping(uint => PositionInfo) storage positions,
        uint[] calldata positionIndexes
    ) public returns (PositionBalanceV3[] memory) {
        PositionBalanceV3[] memory balances = new PositionBalanceV3[](positionIndexes.length);
        for (uint i = 0; i < positionIndexes.length; ++i) {
            balances[i] = getV3(main, positions[positionIndexes[i]]);
        }
        return balances;
    }

    function getV3(IMinimaxMain main, PositionInfo storage position) public returns (PositionBalanceV3 memory result) {
        if (position.closed) {
            return result;
        }

        IPoolAdapter adapter = main.poolAdapters(uint256(keccak256(position.poolAddress.code)));

        result.gasTank = address(position.callerAddress).balance;
        result.stakedAmount = position.stakedAmount;
        result.poolStakedAmount = position.callerAddress.stakingBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );
        result.poolRewardAmounts = position.callerAddress.rewardBalances(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );

        return result;
    }

    function getManyV2(
        IMinimaxMain main,
        mapping(uint => PositionInfo) storage positions,
        uint[] calldata positionIndexes
    ) public returns (PositionBalanceV2[] memory) {
        PositionBalanceV2[] memory balances = new PositionBalanceV2[](positionIndexes.length);
        for (uint i = 0; i < positionIndexes.length; ++i) {
            balances[i] = getV2(main, positions[positionIndexes[i]]);
        }
        return balances;
    }

    function getV2(IMinimaxMain main, PositionInfo storage position) public returns (PositionBalanceV2 memory) {
        if (position.closed) {
            return PositionBalanceV2({gasTank: 0, stakedAmount: 0, poolStakedAmount: 0, poolRewardAmount: 0});
        }

        IPoolAdapter adapter = main.poolAdapters(uint256(keccak256(position.poolAddress.code)));

        uint gasTank = address(position.callerAddress).balance;
        uint stakingBalance = position.callerAddress.stakingBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );
        uint rewardBalance = position.callerAddress.rewardBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );

        return
            PositionBalanceV2({
                gasTank: gasTank,
                stakedAmount: position.stakedAmount,
                poolStakedAmount: stakingBalance,
                poolRewardAmount: rewardBalance
            });
    }

    function getManyV1(
        IMinimaxMain main,
        mapping(uint => PositionInfo) storage positions,
        uint[] calldata positionIndexes
    ) public returns (PositionBalanceV1[] memory) {
        PositionBalanceV1[] memory balances = new PositionBalanceV1[](positionIndexes.length);
        for (uint i = 0; i < positionIndexes.length; ++i) {
            balances[i] = getV1(main, positions[positionIndexes[i]]);
        }
        return balances;
    }

    function getV1(IMinimaxMain main, PositionInfo storage position) public returns (PositionBalanceV1 memory) {
        if (position.closed) {
            return PositionBalanceV1({total: 0, reward: 0, gasTank: 0});
        }

        IPoolAdapter adapter = main.poolAdapters(uint256(keccak256(position.poolAddress.code)));

        uint gasTank = address(position.callerAddress).balance;
        uint stakingBalance = position.callerAddress.stakingBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );
        uint rewardBalance = position.callerAddress.rewardBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );

        if (position.stakedToken != position.rewardToken) {
            return PositionBalanceV1({total: position.stakedAmount, reward: rewardBalance, gasTank: gasTank});
        }

        uint totalBalance = rewardBalance + stakingBalance;

        if (totalBalance < position.stakedAmount) {
            return PositionBalanceV1({total: totalBalance, reward: 0, gasTank: gasTank});
        }

        return PositionBalanceV1({total: totalBalance, reward: totalBalance - position.stakedAmount, gasTank: gasTank});
    }
}

