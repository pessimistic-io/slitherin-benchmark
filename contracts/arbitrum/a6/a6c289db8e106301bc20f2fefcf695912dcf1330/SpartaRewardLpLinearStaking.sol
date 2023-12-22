//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {LpLinearStaking, SpartaDexPair, IAccessControl} from "./LPLinearStaking.sol";
import {ISpartaStaking} from "./ISpartaStaking.sol";
import {IContractsRepostiory} from "./IContractsRepostiory.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

contract SpartaRewardLpLinearStaking is LpLinearStaking {
    using SafeERC20 for IERC20;

    bytes32 constant SPARTA_STAKING_CONTRACT_ID = keccak256("SPARTA_STAKING");
    IContractsRepostiory public contractsRepository;

    constructor(
        SpartaDexPair _lpToken,
        IERC20 _sparta,
        IAccessControl _acl,
        IContractsRepostiory _contractsRepository,
        address _treasury,
        uint256 _value
    ) LpLinearStaking(_lpToken, _sparta, _acl, _treasury, _value) {
        contractsRepository = _contractsRepository;
    }

    function getReward()
        external
        payable
        override
        isInitialized
        onlyWithFees
        updateReward(msg.sender)
    {
        address spartaStakingAddress = contractsRepository.tryGetContract(
            SPARTA_STAKING_CONTRACT_ID
        );

        uint256 reward = rewards[msg.sender];

        if (reward == 0) {
            revert AmountZero();
        }

        uint256 toTransfer = reward;
        if (spartaStakingAddress != address(0)) {
            ISpartaStaking staking = ISpartaStaking(spartaStakingAddress);

            toTransfer = (reward * 250000) / 1000000;
            uint256 onStaking = reward - toTransfer;

            rewardToken.forceApprove(spartaStakingAddress, onStaking);
            staking.stakeAs(msg.sender, onStaking);
        }

        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, toTransfer);
        emit RewardTaken(msg.sender, toTransfer);
    }
}

