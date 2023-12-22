// SPDX-License-Identifier: MIT

// https://twitter.com/dealmpoker1
// https://discord.gg/hdgaZUqBSs
// https://t.me/+OZenwkiHEpliOGY0
// https://www.facebook.com/dealmpoker

pragma solidity ^0.8.9;

import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./InvestmentPoolsInterface.sol";
import "./Initializable.sol";
import "./RewardPoolsStorage.sol";

contract RewardPools is Initializable, OwnableUpgradeable, RewardPoolsStorage {
    modifier onlyController() {
        require(controller[msg.sender] == true, "Caller is not controller");
        _;
    }

    function createRewardPool(uint256 poolId, uint256 amount) public {
        require(
            InvestmentPoolsInterface(investmentPoolsContractAddress)
                .creatorPerPoolId(poolId) == msg.sender,
            "You are not the pool creator!"
        );

        require(
            amount - ((amount * protocolFeePercentage) / 100) > 0,
            "Reward too low"
        );

        rewardPoolCreatedForPoolId[poolId] = true;
        rewardCheckPeriodForPoolId[poolId] =
            block.timestamp +
            rewardCheckPeriodInSeconds;

        // 5% Protocol Fee
        uint256 protocolFee = (amount * protocolFeePercentage) / 100;

        IERC20(rewardTokenAddress).transferFrom(
            msg.sender,
            protocolFeeReceiver,
            protocolFee
        );

        uint256 reward = amount - protocolFee;

        IERC20(rewardTokenAddress).transferFrom(
            msg.sender,
            address(this),
            reward
        );

        rewardAmountPerPoolId[poolId] += reward;

        emit RewardPoolCreated(msg.sender, poolId, reward, block.timestamp);
    }

    function claimReward(uint256 poolId) public {
        require(
            userClaimedPerPoolId[poolId][msg.sender] == false,
            "You have already claimed!"
        );

        require(
            rewardPoolCreatedForPoolId[poolId] == true,
            "There's not reward pool for this pool id"
        );

        require(
            rewardCheckPeriodForPoolId[poolId] < block.timestamp,
            "Can't claim before checking period expires"
        );

        require(
            InvestmentPoolsInterface(investmentPoolsContractAddress)
                .checkIfUserHasInvestedInPoolId(msg.sender, poolId) == true,
            "You have not invested in this pool!"
        );

        require(
            claimedAmountPerPoolId[poolId] + userReward(msg.sender, poolId) <=
                rewardAmountPerPoolId[poolId],
            "Pool is empty"
        );

        userClaimedPerPoolId[poolId][msg.sender] = true;
        claimedAmountPerPoolId[poolId] += userReward(msg.sender, poolId);

        IERC20(rewardTokenAddress).transfer(
            msg.sender,
            userReward(msg.sender, poolId)
        );

        emit ClaimedReward(
            msg.sender,
            poolId,
            userReward(msg.sender, poolId),
            block.timestamp,
            claimedAmountPerPoolId[poolId]
        );
    }

    function userReward(
        address addr,
        uint256 poolId
    ) public view returns (uint256) {
        uint256 userInvestedBalancePerPool = InvestmentPoolsInterface(
            investmentPoolsContractAddress
        ).getUserBalancePerPool(addr, poolId);

        uint256 amountRaisedPerPool = InvestmentPoolsInterface(
            investmentPoolsContractAddress
        ).getAmountRaisedPerPool(poolId);

        uint256 reward = (userInvestedBalancePerPool *
            rewardAmountPerPoolId[poolId]) / amountRaisedPerPool;

        return reward;
    }

    function setInvestmentPoolsContractAddress(
        address _newInvestmentPoolsContractAddress
    ) external virtual onlyController {
        investmentPoolsContractAddress = _newInvestmentPoolsContractAddress;
    }

    function setRewardTokenAddress(
        address _newRewardTokenAddress
    ) external virtual onlyController {
        rewardTokenAddress = _newRewardTokenAddress;
    }

    function setRewardCheckPeriodInSeconds(
        uint256 _newRewardCheckPeriodInSeconds
    ) external virtual onlyController {
        rewardCheckPeriodInSeconds = _newRewardCheckPeriodInSeconds;
    }

    function setProtocolFeeReceiver(
        address _newProtocolFeeReceiver
    ) external virtual onlyController {
        protocolFeeReceiver = _newProtocolFeeReceiver;
    }

    function setProtocolFeePercentage(
        uint256 _newProtocolFeePercentage
    ) external virtual onlyController {
        protocolFeePercentage = _newProtocolFeePercentage;
    }

    function setController(
        address _addr,
        bool _value
    ) external virtual onlyOwner {
        controller[_addr] = _value;
    }
}

