// SPDX-License-Identifier: bsl-1.1
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./IPriceOracle.sol";
import "./ICoreMultidataFeedsReader.sol";

contract MultidataPriceOracle is IPriceOracle, Ownable {

    uint private constant MULTIDATA_FEEDS_COEFF = 2**112;

    ICoreMultidataFeedsReader public immutable multidataFeeds;
    uint32 public immutable timeout;

    struct CTokenConfig {
        uint8 decimals;
        string metricName;
    }

    mapping(address => CTokenConfig) public cTokenConfigs;

    constructor(address multidataFeeds_, uint32 timeout_) {
        require(multidataFeeds_ != address(0), "Invalid address");
        multidataFeeds = ICoreMultidataFeedsReader(multidataFeeds_);
        timeout = timeout_;
    }

    function getUnderlyingPrice(address cToken) external view returns (uint) {
        string memory metricName = cTokenConfigs[cToken].metricName;
        if (bytes(metricName).length == 0) {
            return 0;
        }

        uint256 underlyingDecimals = cTokenConfigs[cToken].decimals;

        string[] memory metrics = new string[](1);
        metrics[0] = metricName;
        try multidataFeeds.quoteMetrics(metrics)
            returns (ICoreMultidataFeedsReader.Quote[] memory quotes) {

            if (block.timestamp - timeout >= quotes[0].updateTS) {
                return 0;
            }

            // from the current oracle https://etherscan.io/address/0x50ce56A3239671Ab62f185704Caedf626352741e#code
            // Comptroller needs prices in the format: ${raw price} * 1e36 / baseUnit
            // The baseUnit of an asset is the amount of the smallest denomination of that asset per whole.
            // For example, the baseUnit of ETH is 1e18.

            return quotes[0].value // price from multidata oracle, which is adjusted as 2^112 for a whole
                * 10**(36 - underlyingDecimals) // adjustment of a comptroller price
                / MULTIDATA_FEEDS_COEFF; // remove multidata oracle adjustment
        } catch {
            return 0;
        }
    }

    function isPriceOracle() external pure returns (bool) {
        return true;
    }

    function setTokensConfig(address[] calldata tokens_, CTokenConfig[] calldata configs_) external onlyOwner {
        require(tokens_.length == configs_.length && tokens_.length != 0, "Invalid arrays length");

        for (uint i=0; i<tokens_.length; ++i) {
            require(tokens_[i] != address(0), "Invalid token address");

            cTokenConfigs[tokens_[i]] = configs_[i];
        }
    }
}

