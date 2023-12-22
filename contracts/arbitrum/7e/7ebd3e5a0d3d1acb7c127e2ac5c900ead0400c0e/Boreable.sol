//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface Boreable {
    function userBurn(address account, uint256 amount) external;
    function userReward(address account, uint256 amount) external;
}
