// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IPrimeOracleGetter.sol";

/**
 * @title PrimeOracleStorage
 * @author Prime
 * @notice The core interface for the Prime Oracle storage variables
 */
abstract contract PrimeOracleStorage {
    address public uspAddress;
    // Map of asset price feeds (chainasset => priceSource)
    mapping(uint256 => mapping(address => IPrimeOracleGetter)) public primaryFeeds;
    mapping(uint256 => mapping(address => IPrimeOracleGetter)) public secondaryFeeds;
    uint8 public immutable RATIO_DECIMALS = 18;
}
