// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IOreoVault {
    function safeTransferOreo(address _account, uint256 _amount) external;
}

