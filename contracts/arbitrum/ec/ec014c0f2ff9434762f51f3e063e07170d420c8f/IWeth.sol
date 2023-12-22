// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.4;

import "./IERC20.sol";

interface IWeth is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

