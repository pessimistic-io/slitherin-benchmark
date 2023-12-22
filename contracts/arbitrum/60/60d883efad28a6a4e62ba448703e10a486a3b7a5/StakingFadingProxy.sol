// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OnlyWhitelisted } from "./OnlyWhitelisted.sol";
import { IERC20 } from "./IERC20.sol";
import { Interpolating } from "./Interpolating.sol";
import { IStaking } from "./IStaking.sol";
import { IStakingPerRewardController } from "./IStakingPerRewardController.sol";
import { IStakingPerTierController } from "./IStakingPerTierController.sol";
import { SafeERC20 } from "./SafeERC20.sol";


contract StakingFadingProxy is OnlyWhitelisted, Interpolating, IStakingPerRewardController, IStakingPerTierController {
    IStaking public stakingInstance;
    Interpolation public fadeInterpolation;

    constructor(IStaking _stakingInstance) {
        require(address(_stakingInstance) != address(0), "Invalid staking contract address");
        stakingInstance = _stakingInstance;
        // default to no interpolation
        fadeInterpolation = Interpolation(1, 2, 1000000, 1000000);
    }
    
    // some housekeeping
    function setStaking(IStaking _stakingInstance) external onlyOwner {
        require(address(_stakingInstance) != address(0), "Invalid staking contract address");
        stakingInstance = _stakingInstance;
    }
    function setFade(Interpolation calldata _fadeInterpolation) external onlyOwner {
        require(_fadeInterpolation.startOffset > block.number, "Must start in the future");
        fadeInterpolation = _fadeInterpolation;
    }

    // altered proxy calls
    function scaleAmount(uint256 _amount, uint256 _blockNumber) public view returns (uint256) {
        return lerpValue(fadeInterpolation, _blockNumber, _amount);
    }
    function getVestedTokens(address user) external override view returns (uint256) {
        return scaleAmount(stakingInstance.getVestedTokens(user), block.number);
    }
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external override view returns (uint256) {
        return scaleAmount(stakingInstance.getVestedTokensAtSnapshot(user, blockNumber), blockNumber);
    }

    // unaltered proxy calls
    function stakeFor(address _account, uint256 _amount) external {
        // collect the tokens
        IERC20 baseToken = stakingInstance.token();
        uint256 allowance = baseToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Check the token allowance");
        SafeERC20.safeTransferFrom(baseToken, msg.sender, address(this), _amount);

        // stake the tokens onward
        baseToken.approve(address(stakingInstance), _amount);
        stakingInstance.stakeFor(_account, _amount);
    }
    function token() external view override returns (IERC20) {
        return stakingInstance.token();
    }
    function snapshot() external override onlyWhitelisted {
        stakingInstance.snapshot();
    }
    function getStakersCount() external override view returns (uint256) {
        return stakingInstance.getStakersCount();
    }
    function getStakers(uint256 idx) external override view returns (address) {
        return stakingInstance.getStakers(idx);
    }
}

