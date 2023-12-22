//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IEpochBasedLimiter {
    function epochLimit() external view returns (uint);
    function epochDuration() external view returns (uint);
    function currentEpoch() external view returns (uint);
    function currentEpochStart() external view returns (uint);
    function currentEpochCount() external view returns (uint);
    function tryUpdateEpoch() external;
}

