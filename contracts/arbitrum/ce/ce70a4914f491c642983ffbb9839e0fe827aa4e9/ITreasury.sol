// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IAccessControlEnumerableUpgradeable.sol";

interface ITreasury is IAccessControlEnumerableUpgradeable {
    function limitOf(
        address token,
        address spender
    ) external view returns (uint);

    function setSpendLimit(address token, address spender, uint limit) external;

    function increaseSpendLimit(
        address token,
        address spender,
        uint limit
    ) external;

    // Spend functions
    function transfer(address token, address to, uint value) external;

    function approve(address token, address spender, uint value) external;
}

