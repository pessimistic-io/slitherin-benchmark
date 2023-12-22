// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

interface IPriceManager {
    /**
     * @dev Emitted when the new Oracle aggregator data has been added.
     * @param _underlying Address of the underlying asset.
     * @param _strike Address of the strike asset.
     * @param _bhavishAggregator Address of the bhavish aggregator.
     * @param _aggregator Address of the aggregator.
     */
    event AddAssetPairAggregator(
        bytes32 indexed _underlying,
        bytes32 indexed _strike,
        address _bhavishAggregator,
        address _aggregator
    );

    /**
     * @notice Function to add the price for an underlying, strike asset pair
     * @param _underlying Underlying Asset
     * @param _strike Strike Asset
     * @param _aggregator Address of the aggregator.
     */
    function setPairContract(
        bytes32 _underlying,
        bytes32 _strike,
        address _aggregator
    ) external;

    /**
     * @notice Function to get the price for an underlying asset
     * @param _underlying Underlying Asset
     * @param _strike Strike Asset
     * @param _timestamp    Timestamp
     * @return price asset price
     * @return decimals asset price decimals
     */
    function getPrice(
        bytes32 _underlying,
        bytes32 _strike,
        uint256 _timestamp
    ) external view returns (uint256 price, uint8 decimals);
}

