//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
interface IPits {
    function validation() external view returns (bool);

    function getTimeOut() external view returns (uint256);

    function getTimeBelowMinimum() external view returns (uint256);

    function getDaysOff(uint256 _timestamp) external view returns (uint256);

    function getTotalDaysOff() external view returns (uint256);
}

