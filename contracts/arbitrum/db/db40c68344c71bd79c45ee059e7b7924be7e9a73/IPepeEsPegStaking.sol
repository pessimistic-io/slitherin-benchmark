//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { EsPegStake } from "./Structs.sol";

interface IPepeEsPegStaking {
    function stake(uint256 amount) external;

    function claim(uint256 stakeId) external;

    function claimAll() external;

    function pendingRewards(address user) external view returns (uint256 pendingRewards_);

    function getUserStake(address user, uint256 stakeId) external view returns (EsPegStake memory);
}

