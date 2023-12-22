// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./IERC20.sol";

interface rPool {
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}

