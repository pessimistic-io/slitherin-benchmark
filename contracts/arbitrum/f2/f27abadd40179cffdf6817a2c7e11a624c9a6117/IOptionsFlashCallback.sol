// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IOptionsFlashCallback {
    function optionsFlashCallback(address account, uint256 amount, uint256 fee, bytes calldata data) external;
}

