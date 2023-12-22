// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;
import "./ERC20_IERC20Upgradeable.sol";

interface IAccount {
    function initialize() external;

    function flushToken(address token) external;

    function flushToken(address[] calldata tokens) external;

    function flush() external;

    function approve(IERC20Upgradeable token, address spender) external;

    function approve(
        IERC20Upgradeable[] calldata tokens,
        address spender
    ) external;

    function transferOwnership(address newOwner) external;
}

