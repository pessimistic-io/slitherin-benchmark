// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface ITenderComp {
    function mint(uint256 mintAmount) external returns(uint);
    function mint() external payable;
    function redeem(uint256 redeemTokens) external returns(uint);
}

interface ITenderTroller {
    function enterMarkets(address[] calldata cTokens)  external returns (uint[] memory);
    function exitMarket(address cToken)  external returns (uint); 
    function claimComp(address holder) external;
}

interface ITenderInstantVester{
    function instantVest(uint256 amount) external;
}
