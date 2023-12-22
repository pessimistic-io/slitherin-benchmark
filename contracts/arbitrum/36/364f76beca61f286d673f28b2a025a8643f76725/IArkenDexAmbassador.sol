// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IArkenDexAmbassador {
    function tradeWithTarget(
        address srcToken,
        uint256 amountIn,
        bytes calldata interactionDataOutside,
        uint256 valueOutside,
        address targetOutside
    ) external payable;
}

