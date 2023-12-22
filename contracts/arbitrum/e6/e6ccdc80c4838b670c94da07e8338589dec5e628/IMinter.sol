// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IMinter {
    function update_period() external returns (uint);
    // function initialize(address[] memory claimants, uint[] memory amounts, uint max) external;
    function initialize() external;
    function active_period() external view returns (uint);
    function weekly_emission() external view returns (uint);
}
