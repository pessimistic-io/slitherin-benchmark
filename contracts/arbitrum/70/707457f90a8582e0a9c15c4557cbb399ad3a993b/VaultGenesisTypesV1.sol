// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface VaultGenesisTypesV1 {
    struct VaultSetting {
        address owner;
        string name;
        string symbol;
        address denominator;
        uint256 depositFee;
        uint256 withdrawFee;
        uint256 performanceFee;
        uint256 protocolFee;
    }

    /// @notice The basket type
    /// @param tokenAddress The ERC20 address
    /// @param ratio The ratio of ERC20 token in the basket
    /// @param baseChainlinkFeed The ERC20 address of Chainlink contract. E.g. BTC/USD
    /// @param quoteChainlinkFeed The underlying address of Chainlink contract. E.g. USDC/USD
    struct UnderlyingAssetStruct {
        address tokenAddress;
        uint256 ratio; // ratio of the asset in the vault. 500 = 5.00%, 10000 = 100.00%
        uint256 decimals;
    }
}

