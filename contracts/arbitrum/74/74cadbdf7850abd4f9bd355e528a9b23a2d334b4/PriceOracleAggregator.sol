// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IPriceOracleAggregator} from "./IPriceOracleAggregator.sol";
import {IOracle} from "./IOracle.sol";

// Contracts
import {Ownable} from "./Ownable.sol";

contract PriceOracleAggregator is IPriceOracleAggregator, Ownable {
    /// @notice token to the oracle address
    mapping(address => IOracle) public assetToOracle;

    /// @notice adds oracle for an asset e.g. ETH
    /// @param _asset the oracle for the asset
    /// @param _oracle the oracle address
    function updateOracleForAsset(address _asset, IOracle _oracle)
        external
        override
        onlyOwner
    {
        require(
            address(_oracle) != address(0),
            'PriceOracleAggregator: Oracle address cannot be zero address'
        );
        assetToOracle[_asset] = _oracle;
        emit UpdateOracle(_asset, _oracle);
    }

    /// @notice returns price of token in USD in 1e8 decimals
    /// @param _token token to fetch price
    function getPriceInUSD(address _token) external override returns (uint256) {
        require(
            address(assetToOracle[_token]) != address(0),
            'PriceOracleAggregator: Oracle address cannot be zero address'
        );

        uint256 price = assetToOracle[_token].getPriceInUSD();

        require(price > 0, 'PriceOracleAggregator: Price cannot be 0');

        return price;
    }

    /// @notice returns price of token in USD
    /// @param _token view price of token
    function viewPriceInUSD(address _token)
        external
        view
        override
        returns (uint256)
    {
        require(
            address(assetToOracle[_token]) != address(0),
            'PriceOracleAggregator: Oracle address cannot be zero address'
        );
        return assetToOracle[_token].viewPriceInUSD();
    }
}

