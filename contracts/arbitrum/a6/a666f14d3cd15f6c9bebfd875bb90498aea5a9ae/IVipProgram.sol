// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface IVipProgram {
    function getDiscountable(address _account) external view returns(uint256);
}
