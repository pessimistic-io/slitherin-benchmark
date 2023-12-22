// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IHelper.sol";

interface ILoanAssetMessageHandler {
    function mintFromChain(
        IHelper.LoanAssetBridge memory params,
        uint256 srcChain
    ) external payable;
}
