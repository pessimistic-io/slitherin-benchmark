// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";

import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";
import { LibOracle } from "./LibOracle.sol";

import "./console.sol";

error NotWhitelistedAddress();


contract StrategPortalOracleFacet is UsingDiamondOwner {
    using SafeERC20 for IERC20;

    event OracleWhitelistChanged(address indexed addr, bool whitelisted);
    event OracleRateChanged(address indexed asset, uint256 price);
    event OracleEnabled(address indexed asset, uint8 decimals);
    event OracleDisabled(address indexed asset);

    constructor() {}

    function whitelistOracle(bool _enable, address _addr) external onlyOwner {
        LibOracle.setUpdater(_enable, _addr);
        emit OracleWhitelistChanged(_addr, _enable);
    }

    function getOracleRates(
        address[] memory _froms, 
        address[] memory _to,
        uint256[] memory _amount
    ) external view returns (uint256[] memory) {
        uint256 fromLength = _froms.length;
        require(fromLength == _to.length && fromLength == _amount.length, "");

        uint256 ratesLength = _froms.length;
        uint256[] memory rates = new uint256[](ratesLength);

        for (uint i = 0; i < ratesLength; i++) {
            rates[i] = LibOracle.getRate(_froms[i], _to[i], _amount[i]);
        }

        return rates;
    }

    function getOraclePrices(
        address[] memory _assets
    ) external view returns (uint256[] memory) {

        uint256 pricesLength = _assets.length;
        uint256[] memory prices = new uint256[](pricesLength);

        for (uint i = 0; i < pricesLength; i++) {
            prices[i] = LibOracle.getPrice(_assets[i]);
        }

        return prices;
    }

    function updateOraclePrice(
        address[] memory _addresses, 
        uint256[] memory _prices
    ) external {
        if(!LibOracle.isUpdater(msg.sender)) revert NotWhitelistedAddress();

        for (uint i = 0; i < _addresses.length; i++) {
            LibOracle.setPrice(_addresses[i], _prices[i]);
            emit OracleRateChanged(_addresses[i], _prices[i]);
        }
    }

    function oraclePricesAreEnable(
        address[] calldata _assets
    ) external view returns (bool[] memory) {
        bool[] memory enabledPrices = new bool[](_assets.length);
        for (uint i = 0; i < _assets.length; i++) {
            enabledPrices[i] = LibOracle.priceIsEnabled(_assets[i]);
        }

        return enabledPrices;
    }

    function enableOraclePrice(
        address _asset, 
        uint8 _assetDecimals
    ) external {
        if(!LibOracle.isUpdater(msg.sender)) revert NotWhitelistedAddress();

        LibOracle.enablePrice(
            _asset, 
            _assetDecimals
        );
        emit OracleEnabled(_asset, _assetDecimals);
    }

    function disableOraclePrice(
        address _asset
    ) external {
        if(!LibOracle.isUpdater(msg.sender)) revert NotWhitelistedAddress();

        LibOracle.disablePrice(_asset);
        emit OracleDisabled(_asset);
    }
}

