// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBespokeBasketV1 {
    function tokenPortions(address _contract) external view returns (uint256);
    function buyFromBasket(uint256 amount) external;
    function redeem(uint256 amount) external;
    function create(uint256 amount) external;
}

