// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.5.0;

interface ComptrollerInterface {
    function _supportMarket(address) external returns (uint256);
    function _setCollateralFactor(address, uint256) external returns (uint256);
    function _setBorrowPaused(address, bool) external returns (bool);
}

