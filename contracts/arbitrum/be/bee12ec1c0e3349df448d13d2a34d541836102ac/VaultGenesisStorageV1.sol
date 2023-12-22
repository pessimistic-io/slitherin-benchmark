// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { VaultGenesisTypesV1 } from "./VaultGenesisTypesV1.sol";
import { IERC20 } from "./IERC20.sol";

contract VaultGenesisStorageV1 is VaultGenesisTypesV1 {
    IERC20 public denominator;

    uint8 public denominatorDecimals;

    bool public vaultStarted;

    UnderlyingAssetStruct[] public underlyingAssets;

    address public governor;

    address public manager;

    address public aggregationRouter;

    /// @notice The deposit and withdraw recipient
    address public feeRecipient; // max 10_000

    /// @notice The deposit fee
    uint256 public depositFee; // max 10_000

    /// @notice The withdraw fee
    uint256 public withdrawFee; // max 10_000

    uint256 public performanceFee; // max 10_000

    uint256 public protocolFee; // max 10_000

    mapping(address => bool) internal whitelisted;

    bool public whitelistEnabled;
}

