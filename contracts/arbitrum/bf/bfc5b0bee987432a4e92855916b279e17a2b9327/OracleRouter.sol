// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "./AggregatorV3Interface.sol";
import { IOracle } from "./IOracle.sol";
import { Helpers } from "./Helpers.sol";
import "./console.sol";


abstract contract OracleRouterBase is IOracle {
    uint256 constant MIN_DRIFT = uint256(70000000);
    uint256 constant MAX_DRIFT = uint256(130000000);

    /**
     * @dev The price feed contract to use for a particular asset.
     * @param asset address of the asset
     * @return address address of the price feed for the asset
     */
    function feed(address asset) internal view virtual returns (address);

    /**
     * @notice Returns the total price in 8 digit USD for a given asset.
     * @param asset address of the asset
     * @return uint256 USD price of 1 of the asset, in 8 decimal fixed
     */
    function price(address asset) external view override returns (uint256) {
        address _feed = feed(asset);
        //require(_feed != address(0), "Asset not available: Price");
        (, int256 _iprice, , , ) = AggregatorV3Interface(_feed)
            .latestRoundData();
        uint256 _price = uint256(_iprice);
        if (isStablecoin(asset)) {
            require(_price <= MAX_DRIFT, "Oracle: Price exceeds max");
            require(_price >= MIN_DRIFT, "Oracle: Price under min");
        }
        return uint256(_price);
    }

    function isStablecoin(address _asset) internal view returns (bool) {
        string memory symbol = Helpers.getSymbol(_asset);
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return
            symbolHash == keccak256(abi.encodePacked("DAI")) ||
            symbolHash == keccak256(abi.encodePacked("USDC")) ||
            symbolHash == keccak256(abi.encodePacked("USDT"));
    }
}

contract OracleRouter is OracleRouterBase {
    /**
     * @dev The price feed contract to use for a particular asset.
     * @param asset address of the asset
     */
    function feed(address asset) internal pure override returns (address) {
        if (asset == address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1)) {
            // Chainlink: DAI/USD
            return address(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB);
        } else if (asset == address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8)) {
            // Chainlink: USDC/USD
            return address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
        } else if (asset == address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9)) {
            // Chainlink: USDT/USD
            return address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7); //old 0x0A6513e40db6EB1b165753AD52E80663aeA50545                    
        } else {
            revert("Asset not available");
        }
    }
    
}

contract OracleRouterDev is OracleRouterBase {
    mapping(address => address) public assetToFeed;

    function setFeed(address _asset, address _feed) external {
        assetToFeed[_asset] = _feed;
    }

    /**
     * @dev The price feed contract to use for a particular asset.
     * @param asset address of the asset
     */
    function feed(address asset) internal view override returns (address) {
        return assetToFeed[asset];
    }
}
