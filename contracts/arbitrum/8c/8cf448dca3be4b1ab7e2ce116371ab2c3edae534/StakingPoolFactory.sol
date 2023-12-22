// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {ClonesWithImmutableArgs} from "./ClonesWithImmutableArgs.sol";
import "./IStakingPool.sol";
import "./Ownable.sol";

/// Modified version of https://github.com/ZeframLou/playpen/blob/main/src/StakingPoolFactory.sol
contract StakingPoolFactory is Ownable {
    using ClonesWithImmutableArgs for address;
    event CreateERC20StakingPool(address indexed stakingPool);

    function createERC20StakingPool(
        address erc20StakingPoolImpl,
        address rewardToken,
        address stakeToken,
        uint64 secondDuration
    ) external onlyOwner returns (address stakingPool) {
        bytes memory data = abi.encodePacked(rewardToken, stakeToken, secondDuration);

        stakingPool = erc20StakingPoolImpl.clone(data);
        IStakingPool(stakingPool).initialize(msg.sender);

        emit CreateERC20StakingPool(stakingPool);
    }
}
