// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import { OnlyWhitelisted } from "./OnlyWhitelisted.sol";
import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { Math } from "./Math.sol";
import { Interpolating } from "./Interpolating.sol";
import { IStakingPerRewardController } from "./IStakingPerRewardController.sol";
import { IStakingPerTierController } from "./IStakingPerTierController.sol";
import { IStakingPerLegacyTierReward } from "./IStakingPerLegacyTierReward.sol";
import { SafeERC20 } from "./SafeERC20.sol";


contract StakingGroup is OnlyWhitelisted, Interpolating, IStakingPerRewardController, IStakingPerTierController {
    using SafeMath for uint256;
    IStakingPerLegacyTierReward[] public members;
    IStakingPerLegacyTierReward public primaryStaking;

    mapping(address => bool) public isSnapshotter;

    constructor(IStakingPerLegacyTierReward[] memory _members) {
        members = _members;
    }

    // some housekeeping
    function addStaking(IStakingPerLegacyTierReward _stakingInstance) external onlyOwner {
        require(address(_stakingInstance) != address(0), "Invalid staking contract address");
        members.push(_stakingInstance);

        if (primaryStaking == IStakingPerLegacyTierReward(address(0))) {
            setPrimaryStaking(_stakingInstance);
        }
    }
    function setStaking(uint256 _idx, IStakingPerLegacyTierReward _stakingInstance) external onlyOwner {
        require(_idx < members.length, "Can only set an existing staking");
        members[_idx] = _stakingInstance;
    }
    function setPrimaryStaking(IStakingPerLegacyTierReward _stakingInstance) public onlyOwner {
        require(address(_stakingInstance) != address(0), "Invalid staking contract address");
        primaryStaking = _stakingInstance;
    }

    // summarized proxy calls
    function getVestedTokens(address user) external override view returns (uint256) {
        uint256 result = 0;
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            result = result.add(targetContract.getVestedTokens(user));
        }
        return result;
    }
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external override view returns (uint256) {
        uint256 result = 0;
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            result = result.add(targetContract.getVestedTokensAtSnapshot(user, blockNumber));
        }
        return result;
    }
    function getStakers(uint256 idx) external override view returns (address) {
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            uint256 count = targetContract.getStakersCount();
            if (idx >= count) {
                // we've moved past this contract, adjust idx and continue
                idx = idx.sub(count);
                continue;
            }

            // we can get from this contract
            return targetContract.getStakers(idx);
        }
        require(false, 'No staker found');
    }
    function getStakersCount() external override view returns (uint256) {
        uint256 result = 0;
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            result = result.add(targetContract.getStakersCount());
        }
        return result;
    }

    // unaltered proxy calls
    function stakeFor(address _account, uint256 _amount) external {
        if (address(primaryStaking) == address(0)) {
            require(false, "No primary staking contract set");
        }

        // collect the tokens
        IERC20 baseToken = primaryStaking.token();
        uint256 allowance = baseToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Check the token allowance");
        SafeERC20.safeTransferFrom(baseToken, msg.sender, address(this), _amount);

        // stake the tokens onward
        baseToken.approve(address(primaryStaking), _amount);
        primaryStaking.stakeFor(_account, _amount);
    }
    function token() external view override returns (IERC20) {
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            return IStakingPerLegacyTierReward(members[i]).token();
        }
        return IERC20(address(0));
    }
    function snapshot() external override onlyWhitelisted {
        for(uint i=0; i < members.length; i++) {
            IStakingPerLegacyTierReward targetContract = members[i];
            if (address(targetContract) == address(0)) {
                continue; // skip removed contracts
            }

            IStakingPerLegacyTierReward(members[i]).snapshot();
        }
    }
}

