// SPDX-License-Identifier: MIT

import "./IVault.sol";
import "./IVaultPriceFeed.sol";
import "./IBasePositionManager.sol";
import "./IMlpManager.sol";

import "./SafeMath.sol";

pragma solidity 0.6.12;

contract VaultReader {
    using SafeMath for uint256;

    /// @notice Get the amount of tokens a vault is exposed to
    /// @return The amount of tokens a vault is exposed to in token decimals
    function getTokenExposure(
        address _vault,
        address token,
        bool maximise
    ) public view returns (uint256) {
        IVault vault = IVault(_vault);

        bool isWhitelisted = vault.whitelistedTokens(token);

        if (!isWhitelisted) {
            return 0;
        } else if (vault.stableTokens(token)) {
            return 0;
        }

        uint256 price = maximise ? vault.getMaxPrice(token) : vault.getMinPrice(token);
        uint256 poolAmount = vault.poolAmounts(token);
        uint256 decimals = vault.tokenDecimals(token);
        uint256 reservedAmount = vault.reservedAmounts(token);

        uint256 shortOpenInterest = vault.globalShortSizes(token);

        // poolAmount and reservedAmount both factor in collateral reserved for longOpenInterest
        uint256 aum = (poolAmount.sub(reservedAmount).mul(price).div(10**decimals)).sub(shortOpenInterest);

        // add global short profit / loss since globalShortSize is a dollar denominated value
        if (shortOpenInterest > 0) {
            uint256 averagePrice = vault.globalShortAveragePrices(token);
            uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
            uint256 delta = shortOpenInterest.mul(priceDelta).div(averagePrice);
            if (price > averagePrice) {
                // add losses from shorts
                aum = aum.add(delta);
            } else {
                aum = aum.sub(delta);
            }
        }

        return aum.mul(10**decimals).div(price);
    }

    /// @notice Gets the vaults exposure to an array of tokens
    /// @return An array containing the exposure and the exposure per dollar for each token
    function getVaultExposure(
        address vault,
        address _mlpManager,
        address _weth,
        address[] memory _tokens
    ) public view returns (uint256[] memory) {
        uint256 propsLength = 2;

        IMlpManager mlpManager = IMlpManager(_mlpManager);

        uint256[] memory aums = mlpManager.getAums();
        uint256 aum = (aums[0].add(aums[1])).div(2);

        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            uint256 minExposure = getTokenExposure(vault, token, false);
            uint256 maxExposure = getTokenExposure(vault, token, true);
            uint256 tokenExposure = (minExposure.add(maxExposure)).div(2);

            amounts[i * propsLength] = tokenExposure;
            amounts[i * propsLength + 1] = tokenExposure.mul(10**30).div(aum);
        }

        return amounts;
    }

    function getVaultTokenInfoV3(
        address _vault,
        address _positionManager,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) public view returns (uint256[] memory) {
        uint256 propsLength = 14;

        IVault vault = IVault(_vault);
        IVaultPriceFeed priceFeed = IVaultPriceFeed(vault.priceFeed());
        IBasePositionManager positionManager = IBasePositionManager(_positionManager);

        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            amounts[i * propsLength] = vault.poolAmounts(token);
            amounts[i * propsLength + 1] = vault.reservedAmounts(token);
            amounts[i * propsLength + 2] = vault.usdgAmounts(token);
            amounts[i * propsLength + 3] = vault.getRedemptionAmount(token, _usdgAmount);
            amounts[i * propsLength + 4] = vault.tokenWeights(token);
            amounts[i * propsLength + 5] = vault.bufferAmounts(token);
            amounts[i * propsLength + 6] = vault.maxUsdgAmounts(token);
            amounts[i * propsLength + 7] = vault.globalShortSizes(token);
            amounts[i * propsLength + 8] = positionManager.maxGlobalShortSizes(token);
            amounts[i * propsLength + 9] = vault.getMinPrice(token);
            amounts[i * propsLength + 10] = vault.getMaxPrice(token);
            amounts[i * propsLength + 11] = vault.guaranteedUsd(token);
            amounts[i * propsLength + 12] = priceFeed.getPrimaryPrice(token, false);
            amounts[i * propsLength + 13] = priceFeed.getPrimaryPrice(token, true);
        }

        return amounts;
    }

    function getVaultTokenInfoV4(
        address _vault,
        address _positionManager,
        address _weth,
        uint256 _usdgAmount,
        address[] memory _tokens
    ) public view returns (uint256[] memory) {
        uint256 propsLength = 15;

        IVault vault = IVault(_vault);
        IVaultPriceFeed priceFeed = IVaultPriceFeed(vault.priceFeed());
        IBasePositionManager positionManager = IBasePositionManager(_positionManager);

        uint256[] memory amounts = new uint256[](_tokens.length * propsLength);
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            if (token == address(0)) {
                token = _weth;
            }

            amounts[i * propsLength] = vault.poolAmounts(token);
            amounts[i * propsLength + 1] = vault.reservedAmounts(token);
            amounts[i * propsLength + 2] = vault.usdgAmounts(token);
            amounts[i * propsLength + 3] = vault.getRedemptionAmount(token, _usdgAmount);
            amounts[i * propsLength + 4] = vault.tokenWeights(token);
            amounts[i * propsLength + 5] = vault.bufferAmounts(token);
            amounts[i * propsLength + 6] = vault.maxUsdgAmounts(token);
            amounts[i * propsLength + 7] = vault.globalShortSizes(token);
            amounts[i * propsLength + 8] = positionManager.maxGlobalShortSizes(token);
            amounts[i * propsLength + 9] = positionManager.maxGlobalLongSizes(token);
            amounts[i * propsLength + 10] = vault.getMinPrice(token);
            amounts[i * propsLength + 11] = vault.getMaxPrice(token);
            amounts[i * propsLength + 12] = vault.guaranteedUsd(token);
            amounts[i * propsLength + 13] = priceFeed.getPrimaryPrice(token, false);
            amounts[i * propsLength + 14] = priceFeed.getPrimaryPrice(token, true);
        }

        return amounts;
    }
}

