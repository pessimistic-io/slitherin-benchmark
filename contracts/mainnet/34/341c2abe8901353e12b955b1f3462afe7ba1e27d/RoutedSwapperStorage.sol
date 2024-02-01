// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./EnumerableSet.sol";
import "./IRoutedSwapper.sol";
import "./DataTypes.sol";

abstract contract RoutedSwapperStorage is IRoutedSwapper {
    /**
     * @notice List of the supported exchanges
     */
    EnumerableSet.AddressSet internal allExchanges;

    /**
     * @notice Mapping of exchanges' addresses by type
     */
    mapping(DataTypes.ExchangeType => address) public addressOf;

    /**
     * @notice Default swap routings
     * @dev Used to save gas by using a preset routing instead of looking for the best
     */
    mapping(bytes => bytes) public defaultRoutings;
}

