// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IDiscount {
    function discountOf(address _user) external view returns (uint256);
    function endTime() external view returns (uint256);
}
