// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IAuctionTreasury {
    function transferLVL(address _to, uint256 _amount) external;
    function distribute() external;
}

