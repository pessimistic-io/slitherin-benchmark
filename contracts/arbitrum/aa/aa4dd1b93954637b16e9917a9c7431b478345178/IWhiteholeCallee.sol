// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

interface IWhiteholeCallee {
    function whiteholeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

