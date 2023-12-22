// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0 <=0.8.19;

import "./IMauser.sol";
import "./IMauserFlashLoanProvider.sol";

abstract contract MauserFlashLoanProvider is IMauserFlashLoanProvider {
    IMauser internal immutable MAUSER;

    constructor(IMauser mauser) {
        MAUSER = mauser;
    }

    function multiSend(bytes memory transactions) internal {
        (bool success,) = MAUSER.getImplementation().delegatecall(abi.encodeWithSignature("multiSend(bytes)", transactions));
        require(success);
    }
}

