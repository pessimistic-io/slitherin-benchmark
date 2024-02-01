// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

interface IErc20Interface {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);

    function exchangeRateCurrent() external returns (uint);
}

interface IEtherInterface {
    function mint() external payable;
    function redeem(uint redeemTokens) external returns (uint);
}
