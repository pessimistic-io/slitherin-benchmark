// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./SafeMath.sol";
import "./AggregatorV3Interface.sol";
import "./Denominations.sol";

import "./YINAccessControl.sol";
import "./IPriceOracle.sol";

contract PriceOracle is IPriceOracle, YINAccessControl {
    using SafeMath for uint256;

    mapping(address => address) public assetToUSD;
    mapping(address => address) public assetToETH;

    address public immutable USD;
    address public immutable WETH;
    uint8 public constant ASSET_TO_USD_DECIMALS = 8;
    uint8 public constant ASSET_TO_ETH_DECIMALS = 18;
    uint256 public TIME_INTERVAL = 30 minutes;

    constructor(PriceOracleConstructorParams memory params) {
        WETH = params.weth;
        USD = Denominations.USD;
        for (uint256 idx = 0; idx < params.assetToUSD.length; idx++) {
            PriceRegistryInputParams memory inputs = params.assetToUSD[idx];
            uint8 decimals = AggregatorV3Interface(inputs.registry).decimals();
            require(
                decimals == ASSET_TO_USD_DECIMALS,
                "PriceOracle: ASSET_TO_USD_DECIMALS"
            );
            assetToUSD[inputs.underlying] = inputs.registry;
        }

        for (uint256 idx = 0; idx < params.assetToETH.length; idx++) {
            PriceRegistryInputParams memory inputs = params.assetToETH[idx];
            uint8 decimals = AggregatorV3Interface(inputs.registry).decimals();
            require(
                decimals == ASSET_TO_ETH_DECIMALS,
                "PriceOracle: ASSET_TO_ETH_DECIMALS"
            );
            assetToETH[inputs.underlying] = inputs.registry;
        }

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // VIEW
    // All USD registry decimals is 8, all ETH registry decimals is 18

    function _getTwapPrice(address registry) internal view returns (uint256) {
        require(registry != address(0), "PriceOracle: IUT");
        (
            uint80 roundId,
            int256 _price,
            ,
            uint256 latestUpdatedAt,

        ) = AggregatorV3Interface(registry).latestRoundData();

        require(_price > 0, "PriceOracle: PLZ");
        require(roundId >= 0, "PriceOracle: Not enough history");
        uint256 beginAt = uint256(block.timestamp).sub(TIME_INTERVAL);
        if (latestUpdatedAt < beginAt || roundId == 0) {
            return uint256(_price);
        }
        uint256 cumulativeTime = uint256(block.timestamp).sub(latestUpdatedAt);
        uint256 prevUpdateAt = latestUpdatedAt;
        uint256 weightedPrice = uint256(_price).mul(cumulativeTime);
        for (; roundId > 0; ) {
            roundId--;
            (
                ,
                int256 _priceTemp,
                ,
                uint256 currentUpdateAt,

            ) = AggregatorV3Interface(registry).getRoundData(roundId);
            require(_priceTemp > 0, "PriceOracle: PLZ");
            if (currentUpdateAt <= beginAt) {
                weightedPrice = weightedPrice.add(
                    uint256(_priceTemp).mul(prevUpdateAt.sub(beginAt))
                );
                break;
            }
            weightedPrice = weightedPrice.add(
                uint256(_priceTemp).mul(prevUpdateAt.sub(currentUpdateAt))
            );
            cumulativeTime = cumulativeTime.add(
                prevUpdateAt.sub(currentUpdateAt)
            );
            prevUpdateAt = currentUpdateAt;
        }
        return weightedPrice.div(TIME_INTERVAL);
    }

    // Return 1e8
    function getUSDPriceByUnderlying(address underlying)
        external
        view
        override
        returns (uint256)
    {
        uint256 price = 0;
        if (assetToUSD[underlying] != address(0)) {
            price = _getTwapPrice(assetToUSD[underlying]);
        } else if (
            assetToETH[underlying] != address(0) &&
            assetToUSD[WETH] != address(0)
        ) {
            uint256 tokenETHPrice = _getTwapPrice(assetToETH[underlying]);
            uint256 ethUSDPrice = _getTwapPrice(assetToUSD[WETH]);
            price = tokenETHPrice.mul(ethUSDPrice).div(
                10**ASSET_TO_ETH_DECIMALS
            );
        }
        require(price > 0, "PriceOracle: PLZ");
        return price;
    }

    // Returns 1e18
    function getETHPriceByUnderlying(address underlying)
        external
        view
        override
        returns (uint256)
    {
        uint256 price = 0;
        if (assetToETH[underlying] != address(0)) {
            price = _getTwapPrice(assetToETH[underlying]);
        }
        require(price > 0, "price <= 0");
        return price;
    }

    function addUnderlyingRegistry(
        address underlying,
        address registry,
        bool isUSD
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isUSD) {
            require(
                assetToUSD[underlying] == address(0),
                "PriceOracle: USD Exists"
            );
            require(
                AggregatorV3Interface(registry).decimals() ==
                    ASSET_TO_USD_DECIMALS,
                "PriceOracle: USD decimals not match"
            );
            assetToUSD[underlying] = registry;
        } else {
            // assetToETH always have decimals == 18
            require(
                assetToETH[underlying] == address(0),
                "PriceOracle: ETH Exists"
            );
            require(
                AggregatorV3Interface(registry).decimals() ==
                    ASSET_TO_ETH_DECIMALS,
                "PriceOracle: USD decimals not match"
            );
            assetToETH[underlying] = registry;
        }
        emit AddUnderlyingRegistry(underlying, registry);
    }

    function removeUnderlyingRegistry(address underlying, bool isUSD)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (isUSD) {
            emit RemoveUnderlyingRegistry(underlying, assetToUSD[underlying]);
            delete assetToUSD[underlying];
        } else {
            emit RemoveUnderlyingRegistry(underlying, assetToETH[underlying]);
            delete assetToETH[underlying];
        }
    }

    function setInterval(uint256 interval)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit SetInterval(TIME_INTERVAL, interval);
        TIME_INTERVAL = interval;
    }
}

