// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IRouter {
    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external;

    function approvePlugin(address _plugin) external;
}

