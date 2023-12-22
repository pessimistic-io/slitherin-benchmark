// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

interface IWETHGateway {
    function depositETH(address onBehalfOf, uint16 referralCode) external payable;

    function withdrawETH(uint256 amount, address onBehalfOf) external;

    function repayETH(uint256 amount, address onBehalfOf) external payable;

    function borrowETH(uint256 amount, uint16 referralCode) external;

    function withdrawETHWithPermit(
        uint256 amount,
        address to,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) external;
}

