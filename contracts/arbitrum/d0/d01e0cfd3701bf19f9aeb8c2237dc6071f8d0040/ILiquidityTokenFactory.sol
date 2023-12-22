// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20.sol";

interface ILiquidityTokenFactory {
    function deploy(
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        address precomputedAddress
    ) external returns (address);

    function computeAddress(
        string calldata tokenName,
        string calldata tokenSymbol,
        bytes32 salt
    ) external view returns (address);
}

