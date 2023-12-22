// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBrewlabsDiscountManager {
    function discountOf(address _to) external view returns (uint256);
}

