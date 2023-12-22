// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8Token {
    function mint(address account_, uint256 amount_) external;
    function decimals() external returns (uint8);
}
