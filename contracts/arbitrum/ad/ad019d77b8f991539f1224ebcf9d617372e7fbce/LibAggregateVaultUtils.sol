// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 } from "./ERC20.sol";
import { GMX_FEE_STAKED_GLP, TOKEN_USDC, TOKEN_WETH, TOKEN_WBTC, TOKEN_LINK, TOKEN_UNI } from "./constants.sol";
import { Solarray } from "./Solarray.sol";
import { AggregateVaultStorage } from "./AggregateVaultStorage.sol";
import { INettedPositionTracker } from "./INettedPositionTracker.sol";
import { GlpHandler } from "./GlpHandler.sol";

ERC20 constant fsGLP = ERC20(GMX_FEE_STAKED_GLP);

library LibAggregateVaultUtils {
    /**
     * @notice Converts the GLP amount owned by each vault to an array of dollar values.
     * @param _glpPrice The current price of GLP.
     * @return glpAsDollars An array containing the GLP amount owned by each vault as dollar values.
     */
    function glpToDollarArray(AggregateVaultStorage.AVStorage storage _avStorage, uint256 _glpPrice)
        internal
        view
        returns (uint256[5] memory glpAsDollars)
    {
        for (uint256 i = 0; i < 5; i++) {
            glpAsDollars[i] = (_glpPrice * getVaultGlpAttributeBalance(_avStorage, i)) / 1e18;
        }
    }

    /**
     * @notice Retrieves the GLP balance attributed to a vault.
     * @param _vaultIdx The index of the vault.
     * @return _balance The GLP balance attributed to the vault.
     */
    function getVaultGlpAttributeBalance(AggregateVaultStorage.AVStorage storage _avStorage, uint256 _vaultIdx)
        internal
        view
        returns (uint256 _balance)
    {
        uint256 totalGlpBalance = fsGLP.balanceOf(address(this));
        uint256 proportion = getVaultGlpAttributeProportion(_avStorage, _vaultIdx);
        return (totalGlpBalance * proportion) / 1e18;
    }

    /**
     * @notice Calculates the proportion of GLP attributed to a vault. 100% = 1e18, 10% = 0.1e18.
     * @param _vaultIdx The index of the vault.
     * @return _proportion The proportion of GLP attributed to the vault.
     */
    function getVaultGlpAttributeProportion(AggregateVaultStorage.AVStorage storage _avStorage, uint256 _vaultIdx)
        internal
        view
        returns (uint256 _proportion)
    {
        uint256[5] memory _vaultGlpAttribution = _avStorage.vaultGlpAttribution;
        uint256 totalGlpAttribution = Solarray.arraySum(_vaultGlpAttribution);
        if (totalGlpAttribution == 0) return 0;
        return (_vaultGlpAttribution[_vaultIdx] * 1e18) / totalGlpAttribution;
    }

    /**
     * @notice Gets the GLP for all vaults with no Profit and Loss (PNL) adjustments
     * @return _vaultsGlpNoPnl An array containing the GLP with no PNL for each vault
     */
    function getVaultsGlpNoPnl(AggregateVaultStorage.AVStorage storage _avStorage)
        internal
        view
        returns (uint256[5] memory _vaultsGlpNoPnl)
    {
        for (uint256 i = 0; i < 5; i++) {
            _vaultsGlpNoPnl[i] = getVaultGlp(_avStorage, i, 0);
        }
    }

    /**
     * @notice Gets the current Global Liquidity Position (GLP) for all vaults
     * @return _vaultsGlp An array containing the GLP for each vault
     */
    function getVaultsGlp(AggregateVaultStorage.AVStorage storage _avStorage)
        internal
        view
        returns (uint256[5] memory _vaultsGlp)
    {
        uint256 currentEpoch = _avStorage.vaultState.epoch;
        for (uint256 i = 0; i < 5; i++) {
            _vaultsGlp[i] = getVaultGlp(_avStorage, i, currentEpoch);
        }
    }

    /**
     * @notice Calculates the GLP amount owned by a vault at a given epoch.
     * @param _vaultIdx The index of the vault.
     * @param _currentEpoch The epoch number.
     * @return _glpAmount The amount of GLP owned by the vault.
     */
    function getVaultGlp(AggregateVaultStorage.AVStorage storage _avStorage, uint256 _vaultIdx, uint256 _currentEpoch)
        internal
        view
        returns (uint256 _glpAmount)
    {
        uint256 totalGlpBalance = fsGLP.balanceOf(address(this));
        uint256 ownedGlp = (totalGlpBalance * getVaultGlpAttributeProportion(_avStorage, _vaultIdx)) / 1e18;

        _glpAmount = ownedGlp;
        if (_currentEpoch > 0) {
            (,, int256[5] memory glpPnl,) = _avStorage.nettedPositionTracker.settleNettingPositionPnl(
                _avStorage.nettedPositions,
                getCurrentPrices(_avStorage),
                getEpochNettedPrice(_avStorage, _currentEpoch),
                getVaultsGlpNoPnl(_avStorage),
                (_getGlpPrice(_avStorage) * 1e18) / 1e30,
                _avStorage.zeroSumPnlThreshold
            );
            int256 glpDelta = glpPnl[_vaultIdx];
            if (glpPnl[_vaultIdx] < 0 && ownedGlp < uint256(-glpDelta)) {
                _glpAmount = 0;
            } else {
                _glpAmount = uint256(int256(ownedGlp) + glpDelta);
            }
        }
    }

    /**
     * @notice Returns the current prices from GMX.
     * @return _prices An INettedPositionTracker.NettedPrices struct containing the current asset prices
     */
    function getCurrentPrices(AggregateVaultStorage.AVStorage storage _avStorage)
        internal
        view
        returns (INettedPositionTracker.NettedPrices memory _prices)
    {
        GlpHandler glpHandler = _avStorage.glpHandler;
        _prices = INettedPositionTracker.NettedPrices({
            stable: glpHandler.getTokenPrice(TOKEN_USDC, 18),
            eth: glpHandler.getTokenPrice(TOKEN_WETH, 18),
            btc: glpHandler.getTokenPrice(TOKEN_WBTC, 18),
            link: glpHandler.getTokenPrice(TOKEN_LINK, 18),
            uni: glpHandler.getTokenPrice(TOKEN_UNI, 18)
        });
    }

    /**
     * @dev Retrieves the netted prices for a given epoch from storage.
     * @param _epoch The epoch number to get the netted prices for.
     * @return _nettedPrices The netted prices for the given epoch.
     */
    function getEpochNettedPrice(AggregateVaultStorage.AVStorage storage _avStorage, uint256 _epoch)
        internal
        view
        returns (INettedPositionTracker.NettedPrices storage _nettedPrices)
    {
        _nettedPrices = _avStorage.lastNettedPrices[_epoch];
    }

    /**
     * @notice Retrieves the current price of GLP.
     * @return _price The current price of GLP.
     */
    function _getGlpPrice(AggregateVaultStorage.AVStorage storage _avStorage) internal view returns (uint256 _price) {
        _price = _avStorage.glpHandler.getGlpPrice();
    }
}

