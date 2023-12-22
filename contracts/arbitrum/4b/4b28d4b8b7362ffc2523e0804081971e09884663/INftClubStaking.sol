// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;


interface INftClubStaking {
    function nextEpochPoint() external view returns (uint256);
    function epoch() external view returns (uint256);
    function distributor() external view returns (address);
    function setEpochReward(uint256 _epochReward) external;
    function allocateReward() external;
}
