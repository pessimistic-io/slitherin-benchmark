// SPDX-License-Identifier: None

pragma solidity ^0.8.0;

interface IHook {
    function registerHook(address token, bytes calldata data) external;

    function unregisterHook(address token) external;

    function beforeTransferHook(address from, address to, uint256 amount) external returns (bool);

    function afterTransferHook(address from, address to, uint256 amount) external returns (bool);

    function beforeMintHook(address from, address to, uint256 amount) external returns (bool);

    function afterMintHook(address from, address to, uint256 amount) external returns (bool);

    function beforeBurnHook(address from, address to, uint256 amount) external returns (bool);

    function afterBurnHook(address from, address to, uint256 amount) external returns (bool);
}

