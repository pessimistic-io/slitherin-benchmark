// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces_IERC20Metadata.sol";

interface IWETH9 is IERC20Metadata {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    // Only valid for Arbitrum
    function depositTo(address account) external payable;

    function withdrawTo(address account, uint256 amount) external;
}

