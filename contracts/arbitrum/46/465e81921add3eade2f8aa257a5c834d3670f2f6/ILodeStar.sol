// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILodeReward {
    function claim() external returns (uint256);
}

interface ILodeComp {
    function mint(uint256 mintAmount) external returns(uint);
    function redeem(uint256 redeemAmount) external returns(uint);
}

interface ILodeTroller {
    function enterMarkets(address[] calldata cTokens)  external returns (uint[] memory);
    function exitMarket(address cToken)  external returns (uint); 
}
