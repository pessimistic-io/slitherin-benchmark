// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IExternalAction.sol";

interface IFutureTransactExternalAction is IExternalAction {
    event NewFutureTransact(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        bytes metadata
    );

    event FutureTransactResolved(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        bytes metadata
    );


    function depositFutureTransact(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        bytes memory metadata
    ) external payable;

    function runAction(
        CircomData memory circomData,
        bytes memory metadata
    ) external;

    receive() external payable;
}

