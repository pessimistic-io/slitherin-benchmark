// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ======================== ArbitrumDualOracle ========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Authors
// Jon Walch: https://github.com/jonwalch
// Drake Evans: https://github.com/DrakeEvans

// Reviewers
// Dennis: https://github.com/denett

// ====================================================================
import { Timelock2Step } from "./Timelock2Step.sol";
import { ITimelock2Step } from "./ITimelock2Step.sol";
import {     ChainlinkOracleWithMaxDelay,     ConstructorParams as ChainlinkOracleWithMaxDelayParams } from "./ChainlinkOracleWithMaxDelay.sol";
import {     EthUsdChainlinkOracleWithMaxDelay,     ConstructorParams as EthUsdChainlinkOracleWithMaxDelayParams } from "./EthUsdChainlinkOracleWithMaxDelay.sol";
import {     UniswapV3SingleTwapOracle,     ConstructorParams as UniswapV3SingleTwapOracleParams } from "./UniswapV3SingleTwapOracle.sol";
import { DualOracleBase, ConstructorParams as DualOracleBaseParams } from "./DualOracleBase.sol";
import { IDualOracle } from "./IDualOracle.sol";

struct ConstructorParams {
    // = Timelock2Step
    address timelockAddress;
    // = DualOracleBase
    address baseToken0;
    uint8 baseToken0Decimals;
    address quoteToken0;
    uint8 quoteToken0Decimals;
    address baseToken1;
    uint8 baseToken1Decimals;
    address quoteToken1;
    uint8 quoteToken1Decimals;
    // = UniswapV3SingleTwapOracle
    address gmxErc20;
    address wethErc20;
    address uniV3PairAddress;
    uint32 twapDuration;
    // = ChainlinkOracleWithMaxDelay
    address gmxUsdChainlinkFeedAddress;
    uint256 gmxUsdChainlinkMaximumOracleDelay;
    // = EthUsdChainlinkOracleWithMaxDelay
    address ethUsdChainlinkFeed;
    uint256 maxEthUsdOracleDelay;
}

/// @title GMXDualOracle
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice An oracle for the GMX token in Usd terms
contract GmxTokenDualOracle is
    Timelock2Step,
    DualOracleBase,
    UniswapV3SingleTwapOracle,
    ChainlinkOracleWithMaxDelay,
    EthUsdChainlinkOracleWithMaxDelay
{
    /// @notice The address of the GMX Erc20 token contract
    address public immutable GMX_ERC20;

    constructor(
        ConstructorParams memory params
    )
        Timelock2Step()
        DualOracleBase(
            DualOracleBaseParams({
                baseToken0: params.baseToken0,
                baseToken0Decimals: params.baseToken0Decimals,
                quoteToken0: params.quoteToken0,
                quoteToken0Decimals: params.quoteToken0Decimals,
                baseToken1: params.baseToken1,
                baseToken1Decimals: params.baseToken1Decimals,
                quoteToken1: params.quoteToken1,
                quoteToken1Decimals: params.quoteToken1Decimals
            })
        )
        UniswapV3SingleTwapOracle(
            UniswapV3SingleTwapOracleParams({
                uniswapV3PairAddress: params.uniV3PairAddress,
                twapDuration: params.twapDuration,
                baseToken: params.wethErc20,
                quoteToken: params.gmxErc20
            })
        )
        ChainlinkOracleWithMaxDelay(
            ChainlinkOracleWithMaxDelayParams({
                chainlinkFeedAddress: params.gmxUsdChainlinkFeedAddress,
                maximumOracleDelay: params.gmxUsdChainlinkMaximumOracleDelay
            })
        )
        EthUsdChainlinkOracleWithMaxDelay(
            EthUsdChainlinkOracleWithMaxDelayParams({
                ethUsdChainlinkFeedAddress: params.ethUsdChainlinkFeed,
                maxEthUsdOracleDelay: params.maxEthUsdOracleDelay
            })
        )
    {
        _setTimelock({ _newTimelock: params.timelockAddress });
        _registerInterface({ interfaceId: type(IDualOracle).interfaceId });
        _registerInterface({ interfaceId: type(ITimelock2Step).interfaceId });

        GMX_ERC20 = params.gmxErc20;
    }

    // ====================================================================
    // View Helpers
    // ====================================================================

    /// @notice The ```name``` function returns the name of the contract
    /// @return _name The name of the contract
    function name() external pure returns (string memory _name) {
        _name = "GMX Token Token Dual Oracle Chainlink with Staleness Check and Uniswap V3 TWAP";
    }

    // ====================================================================
    // Configuration Setters
    // ====================================================================

    /// @notice The ```setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
    /// @dev Requires msg.sender to be the timelock address
    /// @param newMaxOracleDelay The new max oracle delay
    function setMaximumEthUsdOracleDelay(uint256 newMaxOracleDelay) external override {
        _requireTimelock();
        _setMaximumEthUsdOracleDelay({ _newMaxOracleDelay: newMaxOracleDelay });
    }

    /// @notice The ```setMaximumOracleDelay``` function sets the max oracle delay to determine if Chainlink data is stale
    /// @dev Requires msg.sender to be the timelock address
    /// @param newMaxOracleDelay The new max oracle delay
    function setMaximumOracleDelay(uint256 newMaxOracleDelay) external override {
        _requireTimelock();
        _setMaximumOracleDelay({ _newMaxOracleDelay: newMaxOracleDelay });
    }

    /// @notice The ```setTwapDuration``` function sets the TWAP duration for the Uniswap V3 oracle
    /// @dev Must be called by the timelock
    /// @param newTwapDuration The new TWAP duration
    function setTwapDuration(uint32 newTwapDuration) external override {
        _requireTimelock();
        _setTwapDuration({ _newTwapDuration: newTwapDuration });
    }

    // ====================================================================
    // Price Functions
    // ====================================================================

    /// @notice The ```getGmxPerUsdChainlink``` function returns GMX per USD using the Chainlink oracle
    /// @return isBadData If the Chainlink oracle is stale
    /// @return gmxPerUsd The Gmx per USD price
    function getGmxPerUsdChainlink() public view returns (bool isBadData, uint256 gmxPerUsd) {
        uint256 usdPerGmxChainlinkRaw;
        (isBadData, , usdPerGmxChainlinkRaw) = _getChainlinkPrice();
        gmxPerUsd = (ORACLE_PRECISION * CHAINLINK_FEED_PRECISION) / usdPerGmxChainlinkRaw;
    }

    /// @notice The ```getUsdPerEthChainlink``` function returns USD per ETH using the Chainlink oracle
    /// @return isBadData If the Chainlink oracle is stale
    /// @return usdPerEth The Eth Price is usd units
    function getUsdPerEthChainlink() public view returns (bool isBadData, uint256 usdPerEth) {
        uint256 usdPerEthChainlinkRaw;
        (isBadData, , usdPerEthChainlinkRaw) = _getEthUsdChainlinkPrice();
        usdPerEth = (ORACLE_PRECISION * usdPerEthChainlinkRaw) / CHAINLINK_FEED_PRECISION;
    }

    /// @notice The ```getPricesNormalized``` function returns the normalized prices in human readable form
    /// @dev decimals of underlying tokens match so we can just return _getPrices()
    /// @return isBadDataNormal If the Chainlink oracle is stale
    /// @return priceLowNormal The normalized low price
    /// @return priceHighNormal The normalized high price
    function getPricesNormalized()
        external
        view
        override
        returns (bool isBadDataNormal, uint256 priceLowNormal, uint256 priceHighNormal)
    {
        (isBadDataNormal, priceLowNormal, priceHighNormal) = _getPrices();
    }

    /// @notice The ```calculatePrices``` function calculates the normalized prices in a pure function
    /// @param isBadDataGmxUsdChainlink True if the UsdPerGmxChainlink oracle returns stale data
    /// @param gmxPerUsdChainlink The price of GMX Token in usd units
    /// @param gmxPerWethTwap The price of GMX Token in ether
    /// @param isBadDataEthUsdChainlink True if the UsdPerEthChainlink oracle returns stale data
    /// @param usdPerEthChainlink The price of ether in usd units
    /// @return isBadData True if any of the oracles return stale data
    /// @return priceLow The normalized low price
    /// @return priceHigh The normalized high price
    function calculatePrices(
        bool isBadDataGmxUsdChainlink,
        uint256 gmxPerUsdChainlink,
        uint256 gmxPerWethTwap,
        bool isBadDataEthUsdChainlink,
        uint256 usdPerEthChainlink
    ) external pure returns (bool isBadData, uint256 priceLow, uint256 priceHigh) {
        (isBadData, priceLow, priceHigh) = _calculatePrices({
            isBadDataGmxUsdChainlink: isBadDataGmxUsdChainlink,
            gmxPerUsdChainlink: gmxPerUsdChainlink,
            gmxPerWethTwap: gmxPerWethTwap,
            isBadDataEthUsdChainlink: isBadDataEthUsdChainlink,
            usdPerEthChainlink: usdPerEthChainlink
        });
    }

    function _calculatePrices(
        bool isBadDataGmxUsdChainlink,
        uint256 gmxPerUsdChainlink,
        bool isBadDataEthUsdChainlink,
        uint256 gmxPerWethTwap,
        uint256 usdPerEthChainlink
    ) internal pure returns (bool isBadData, uint256 priceLow, uint256 priceHigh) {
        uint256 arbPerUsdTwap = (gmxPerWethTwap * ORACLE_PRECISION) / usdPerEthChainlink;

        isBadData = isBadDataGmxUsdChainlink || isBadDataEthUsdChainlink;
        priceLow = arbPerUsdTwap < gmxPerUsdChainlink ? arbPerUsdTwap : gmxPerUsdChainlink;
        priceHigh = gmxPerUsdChainlink > arbPerUsdTwap ? gmxPerUsdChainlink : arbPerUsdTwap;
    }

    function _getPrices() internal view returns (bool isBadData, uint256 priceLow, uint256 priceHigh) {
        (bool isBadDataGmxUsdChainlink, uint256 gmxPerUsdChainlink) = getGmxPerUsdChainlink();
        uint256 gmxPerWethTwap = _getUniswapV3Twap();
        (bool isBadDataEthUsdChainlink, uint256 usdPerEthChainlink) = getUsdPerEthChainlink();

        (isBadData, priceLow, priceHigh) = _calculatePrices({
            isBadDataGmxUsdChainlink: isBadDataGmxUsdChainlink,
            gmxPerUsdChainlink: gmxPerUsdChainlink,
            isBadDataEthUsdChainlink: isBadDataEthUsdChainlink,
            gmxPerWethTwap: gmxPerWethTwap,
            usdPerEthChainlink: usdPerEthChainlink
        });
    }

    /// @notice The ```getPrices``` function is intended to return two prices from different oracles
    /// @return isBadData is true when data is stale or otherwise bad
    /// @return priceLow is the lower of the two prices
    /// @return priceHigh is the higher of the two prices
    function getPrices() external view returns (bool isBadData, uint256 priceLow, uint256 priceHigh) {
        (isBadData, priceLow, priceHigh) = _getPrices();
    }
}

