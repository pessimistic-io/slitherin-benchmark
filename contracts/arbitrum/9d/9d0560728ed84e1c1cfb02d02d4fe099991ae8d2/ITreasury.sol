// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface ITreasury {
    function buyBack(uint8 _payToken, uint256 _amount) external;
    function getAmount(uint8 _payToken, uint256 _price) external view returns(address, uint256);
    function getAmountOut(address _pair, address _tokenIn, uint256 _amountIn) external view returns(uint256);
    function isNativeToken(address _token) external view returns(bool);
    function isNativeTokenToPay() external view returns(bool);
}
