// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

abstract contract IIRM {
    function setBorrowRate() external virtual /* OnlyRouter() */ returns (uint256 rate);
    function borrowInterestRatePerBlock() external view virtual returns (uint256);
    function borrowInterestRateDecimals() external view virtual returns (uint8);
}

