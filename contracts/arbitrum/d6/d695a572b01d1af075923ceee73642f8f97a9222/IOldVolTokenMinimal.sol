// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IOldVolTokenMinimal {
    function mintTokens(uint168 tokenAmount) external returns (uint256 tokensMinted);
    function burnTokens(uint168 burnAmount) external returns (uint256 tokensReceived);
}

