// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./RouterStorage.sol";

interface IIsolatedRouter {

    function requestDelegateTrade(
        address pool,
        address account,
        address asset,
        int256 amount,
        string memory symbolName,
        int256[] calldata tradeParams
    ) external payable;


    function executionFee() view external returns (uint256);

}
