// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

library BinaryVaultDataType {
    struct WithdrawalRequest {
        uint256 tokenId; // nft id
        uint256 shareAmount; // share amount
        uint256 underlyingTokenAmount; // underlying token amount
        uint256 timestamp; // request block time
        uint256 minExpectAmount; // Minimum underlying amount which user will receive
        uint256 fee;
    }

    struct BetData {
        uint256 bullAmount;
        uint256 bearAmount;
    }

    struct WhitelistedMarket {
        bool whitelisted;
        uint256 exposureBips; // % 10_000 based value. 100% => 10_000
    }
}

