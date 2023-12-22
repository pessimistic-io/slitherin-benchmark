// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./IDepositWithBeneficiary.sol";
import "./Transferer.sol";
import "./FutureTransactExternalAction.sol";

contract MesonDepositWithBeneficiary is Transferer, IDepositWithBeneficiary {
    FutureTransactExternalAction futureTransactExternalAction;

    constructor(address payable futureTransactExternalActionAddress) {
        futureTransactExternalAction = FutureTransactExternalAction(futureTransactExternalActionAddress);
    }

    function depositWithBeneficiary(
        address erc20TokenAddress,
        uint256 amount,
        address beneficiary,
        uint64 data // = nonce
    ) external returns (bool) {
        transferERC20TokenFromOrCheckETH(
            erc20TokenAddress,
            msg.sender,
            address(this),
            amount
        );
        approveERC20Token(erc20TokenAddress, address(futureTransactExternalAction), amount);
        futureTransactExternalAction.depositFutureTransact(
            erc20TokenAddress,
            amount,
            beneficiary,
            abi.encodePacked(data)
        );

        return true;
    }
}

