// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

interface IDripper {
    function availableFunds() external view returns (uint256);
    function collect() external;
    function collectAndRebase() external;
    function setDripDuration(uint256 _durationSeconds) external;
    function transferToken(address _asset, uint256 _amount) external;
}
