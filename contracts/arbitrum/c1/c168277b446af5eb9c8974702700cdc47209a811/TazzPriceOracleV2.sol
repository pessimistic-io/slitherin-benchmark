// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./console.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {TickMath} from "./TickMath.sol";
import {WadRayMath} from "./WadRayMath.sol";
import {DataTypes} from "./DataTypes.sol";
import {Errors} from "./Errors.sol";
import {IACLManager} from "./IACLManager.sol";
import {IGuildAddressesProvider} from "./IGuildAddressesProvider.sol";
import {ITazzPriceOracle} from "./ITazzPriceOracle.sol";
import {IOracleProxy} from "./IOracleProxy.sol";
import {X96Math} from "./X96Math.sol";

/**
 * @title TazzPriceOracle v1.2
 * @author Tazz Labs
 * @notice Implements the logic to read twap prices from Uniswap V3 Dexs
 **/

contract TazzPriceOracleV2 is ITazzPriceOracle {
    using WadRayMath for uint256;

    IGuildAddressesProvider public immutable ADDRESSES_PROVIDER;

    // Mapping of asset addresses to dex addresses
    mapping(address => address) assetPriceSources;
    
    address public immutable BASE_CURRENCY;
    uint32 public _lookbackPeriod;

    /**
     * @dev Only guild admin can call functions marked by this modifier.
     **/
    modifier onlyGuildAdmin() {
        _onlyGuildAdmin();
        _;
    }

    function _onlyGuildAdmin() internal view {
        address aclManagerAddress = ADDRESSES_PROVIDER.getACLManager();
        require(aclManagerAddress != address(0), Errors.ACL_MANAGER_NOT_SET);
        IACLManager aclManager = IACLManager(aclManagerAddress);
        require(aclManager.isGuildAdmin(msg.sender), Errors.CALLER_NOT_GUILD_ADMIN);
    }

    /**
     * @notice Initializes a TazzPriceOracle structure
     * @param addressesProvider The address of the new PoolAddressesProvider
     * @param baseCurrency The address of the money token on which the debt is denominated in
     * @param lookbackPeriod The lookback period for twap (in seconds)
     **/
    constructor(
        address addressesProvider,
        address baseCurrency,
        uint32 lookbackPeriod
    ) {
        require(lookbackPeriod > 0, Errors.ORACLE_LOOKBACKPERIOD_IS_ZERO);
        ADDRESSES_PROVIDER = IGuildAddressesProvider(addressesProvider);
        BASE_CURRENCY = baseCurrency;
        _lookbackPeriod = lookbackPeriod;
    }

    // Set lookback period for oracle proxies
    function setLookbackPeriod(uint32 lookbackPeriod) external onlyGuildAdmin {
        require(lookbackPeriod > 0, Errors.ORACLE_LOOKBACKPERIOD_IS_ZERO);
        _lookbackPeriod = lookbackPeriod;
    }

    // Sets pool for asset pricing
    function setAssetPriceSources(address[] memory assets, address[] memory sources) external onlyGuildAdmin {
        require(assets.length == sources.length, Errors.ARRAY_SIZE_MISMATCH);
        for (uint256 i = 0; i < assets.length; i++) {
            _setAssetPriceSource(assets[i], sources[i]);
        }
    }

    // Internal function to set the pricing pool for given asset
    function _setAssetPriceSource(address asset, address source) internal {
        // Check to make sure oracle proxy is initialize correctly
        IOracleProxy oracleProxy_ = IOracleProxy(source);
        address token0_ = oracleProxy_.TOKEN0();
        address token1_ = oracleProxy_.TOKEN1();
        address oracleSource_ = oracleProxy_.ORACLE_SOURCE();
        require((asset == token0_ || asset == token1_), Errors.ORACLE_ASSET_MISMATCH);
        // TO DO: Make sure there is a path to base currency

        // Set price source
        assetPriceSources[asset] = source;
    }

    // Get the price source of an asset
    function getPriceSourceOfAsset(address asset) external view returns (address) {
        return assetPriceSources[asset];
    }

    // Fetches twap for asset in base currency terms
    function getAssetPrice(address asset) external view returns (uint256 assetPrice_) {
        // Get Dex Price
        int24 tickAvgPrice = _getAvgTick(asset);
        if (BASE_CURRENCY < asset) tickAvgPrice = -tickAvgPrice;
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tickAvgPrice);
        assetPrice_ = X96Math.getPriceFromSqrtX96(BASE_CURRENCY, asset, sqrtPriceX96);
    }

    function _getAvgTick(address asset) internal view returns (int24 avgTick_) {
        require(assetPriceSources[asset] != address(0), Errors.ASSET_NOT_TRACKED_IN_ORACLE);
        address source_ = assetPriceSources[asset];
        IOracleProxy oracleProxy_ = IOracleProxy(source_);
        avgTick_ = oracleProxy_.getAvgTick(asset, _lookbackPeriod);

        //find avgTick of baseToken if it is not BASE_CURRENCY
        //@dev Tick are in log space, so can be added when seeking to multiply oracle prices together
        address token0_ = oracleProxy_.TOKEN0();
        address token1_ = oracleProxy_.TOKEN1();
        address baseToken_ = (asset == token0_) ? token1_ : token0_;
        if (baseToken_ != BASE_CURRENCY) {
            avgTick_ += _getAvgTick(baseToken_);
        }
    }
}

