//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import { StakedDetails } from "./Structs.sol";

interface IPlutusEpochStaking {
    function currentEpoch() external view returns (uint32);

    function epochCheckpoints(uint32) external view returns (uint32, uint32, uint112);

    function stakedCheckpoints(address, uint32) external view returns (uint112);

    function advanceEpoch() external;

    function init() external;

    function setWhitelist(address) external;

    function pause() external;

    function unpause() external;

    function stakingWindowOpen() external view returns (bool);

    function stake(uint112 _amt) external;

    function unstake() external;

    function claimRewards(uint32 _epoch) external;

    function closeStakingWindow() external;

    function openStakingWindow() external;

    function stakedDetails(address addr) external returns (StakedDetails memory);
}

