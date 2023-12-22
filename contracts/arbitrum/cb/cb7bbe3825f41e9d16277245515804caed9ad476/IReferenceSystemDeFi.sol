// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC20.sol";

interface IReferenceSystemDeFi is IERC20 {
    function burn(uint256 amount) external;
    function generateRandomMoreThanOnce() external;
    function getCrowdsaleDuration() external view returns (uint128);
    function getExpansionRate() external view returns (uint16);
    function getSaleRate() external view returns (uint16);
    function log_2(uint256 x) external pure returns (uint256 y);
    function mintForStakeHolder(address stakeholder, uint256 amount) external;
    function obtainRandomNumber(uint256 modulus) external;
    function withdrawSales(address to) external;
    function updateMaxTxInterval(uint16 maxTxInterval) external;
    function updateMinTxInterval(uint16 minTxInterval) external;
}

