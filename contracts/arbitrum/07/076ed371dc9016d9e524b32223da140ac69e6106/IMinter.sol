// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IMinter {
    function controller() external view returns (address);
    function updatePeriod() external;
}
