// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface ILendVaultStorage {

    function tokenData(address token) external view returns (uint, uint, uint, uint, uint, uint, uint);
    function irmData(address token) external view returns (bool, uint, uint, uint, uint);
    function debtShare(address token, address borrower) external view returns (uint);
    function creditLimits(address token, address borrower) external view returns (uint);
    function borrowerTokens(address borrower, uint index) external view returns (address);
    function tokenBorrowers(address token, uint index) external view returns (address);
    function supportedTokens(uint index) external view returns (address);
    function healthThreshold() external view returns (uint);
    function maxUtilization() external view returns (uint);
    function slippage() external view returns (uint);
    function deleverFeeETH() external view returns (uint);

}

