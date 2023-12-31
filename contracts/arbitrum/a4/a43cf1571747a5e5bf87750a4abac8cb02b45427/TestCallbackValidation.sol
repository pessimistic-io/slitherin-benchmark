// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import "./CallbackValidation.sol";

contract TestCallbackValidation {
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (IRamsesV2Pool pool) {
        return CallbackValidation.verifyCallback(factory, tokenA, tokenB, fee);
    }
}

