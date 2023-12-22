// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IWrappedGLP is IERC20 {

    function deposit(uint256, address) external returns (uint256);

    function redeem(uint256, address, address) external returns (uint256);

    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Harvested(
        address indexed sender,
        uint256 gmxRewards,
        uint256 wethRewards,
        uint256 wethFromGmx,
        uint256 glp
    );
}

