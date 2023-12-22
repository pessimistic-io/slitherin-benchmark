// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./AppleswapEarnCore.sol";

contract AppleswapFarmingFactory is Ownable {
    // immutables
    address public stakingToken;
    uint public stakingGenesis;

    // the reward tokens for which the rewards contract has been deployed
    address[] public rewardTokens;

    // info about rewards for a particular staking token
    struct FarmingInfo {
        address AppleswapEarnCore;
        uint rewardAmount;
        uint duration;
    }

    // rewards info by staking token
    mapping(address => FarmingInfo) public FarmingInfoByRewardToken;

    constructor(address _farmingToken, uint _farmingGenesis) Ownable() {
        require(
            _farmingGenesis >= block.timestamp,
            "AppleswapFarmingFactory::constructor: genesis too soon"
        );

        stakingToken = _farmingToken;
        stakingGenesis = _farmingGenesis;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the reward amount
    // the reward will be distributed to the staking reward contract no sooner than the genesis
    function deploy(
        address rewardToken,
        uint rewardAmount,
        uint256 rewardsDuration
    ) public onlyOwner {
        FarmingInfo storage info = FarmingInfoByRewardToken[rewardToken];
        require(
            info.AppleswapEarnCore == address(0),
            "AppleswapFarmingFactory::deploy: already deployed"
        );

        info.AppleswapEarnCore = address(
            new AppleswapEarnCore(address(this), rewardToken, stakingToken)
        );
        info.rewardAmount = rewardAmount;
        info.duration = rewardsDuration;
        rewardTokens.push(rewardToken);
    }

    function update(
        address rewardToken,
        uint rewardAmount,
        uint256 rewardsDuration
    ) public onlyOwner {
        FarmingInfo storage info = FarmingInfoByRewardToken[rewardToken];
        require(
            info.AppleswapEarnCore != address(0),
            "AppleswapFarmingFactory::update: not deployed"
        );
        info.rewardAmount = rewardAmount;
        info.duration = rewardsDuration;
    }

    function setOwnerForPool(address rewardToken, address newOwner) public onlyOwner {
        FarmingInfo storage info = FarmingInfoByRewardToken[rewardToken];
        require(
            info.AppleswapEarnCore != address(0),
            "AppleswapFarmingFactory::update: not deployed"
        );
        AppleswapEarnCore(info.AppleswapEarnCore).transferOwnership(newOwner);
    }

    ///// permissionless functions

    // call notifyRewardAmount for all staking tokens.
    function notifyRewardAmounts() public onlyOwner {
        require(
            rewardTokens.length > 0,
            "AppleswapFarmingFactory::notifyRewardAmounts: called before any deploys"
        );
        for (uint i = 0; i < rewardTokens.length; i++) {
            notifyRewardAmount(rewardTokens[i]);
        }
    }

    // notify reward amount for an individual staking token.
    // this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    function notifyRewardAmount(address rewardToken) public onlyOwner {
        require(
            block.timestamp >= stakingGenesis,
            "AppleswapFarmingFactory::notifyRewardAmount: not ready"
        );

        FarmingInfo storage info = FarmingInfoByRewardToken[rewardToken];
        require(
            info.AppleswapEarnCore != address(0),
            "AppleswapFarmingFactory::notifyRewardAmount: not deployed"
        );

        if (info.rewardAmount > 0 && info.duration > 0) {
            uint rewardAmount = info.rewardAmount;
            uint256 duration = info.duration;
            info.rewardAmount = 0;
            info.duration = 0;

            require(
                IERC20(rewardToken).transfer(info.AppleswapEarnCore, rewardAmount),
                "AppleswapFarmingFactory::notifyRewardAmount: transfer failed"
            );
            AppleswapEarnCore(info.AppleswapEarnCore).notifyRewardAmount(rewardAmount, duration);
        }
    }

    function pullExtraTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }
}

