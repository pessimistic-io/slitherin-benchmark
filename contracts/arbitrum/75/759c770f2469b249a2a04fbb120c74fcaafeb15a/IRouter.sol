// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./RouterStorage.sol";

interface IRouter {

    function requestDelegateTrade(
        address account,
        string memory symbolName,
        int256[] calldata tradeParams
    ) external payable;


    function executionFee() view external returns (uint256);

}
