// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IVeDepositor {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function depositTokens(uint256 _amount) external returns (bool);
}

