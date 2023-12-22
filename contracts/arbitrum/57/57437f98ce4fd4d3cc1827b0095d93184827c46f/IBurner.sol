// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBurner {
    function isHandler(address _account) external returns (bool);
    function transferAndBurn(address token, uint256 amount) external;
    function setHandler(address _handler, bool _isHandler) external returns (bool);
}

