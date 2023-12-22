// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface IGlpVault {
    function depositGlp(uint256 glpAmount) external;
    function depositGlpFor(uint256 glpAmount, address account) external returns(uint256);
    function withdrawGlp(uint256 shares) external returns(uint256);
}

