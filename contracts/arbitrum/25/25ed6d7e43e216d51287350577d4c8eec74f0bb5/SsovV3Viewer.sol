// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISsovV3} from "./ISsovV3.sol";
import {IERC20} from "./IERC20.sol";

contract SsovV3Viewer {
    /// @notice Returns the strike token addresses for an epoch
    /// @param epoch target epoch
    /// @param ssov target ssov
    function getEpochStrikeTokens(uint256 epoch, ISsovV3 ssov)
        public
        view
        returns (address[] memory strikeTokens)
    {
        uint256[] memory strikes = ssov.getEpochStrikes(epoch);
        strikeTokens = new address[](strikes.length);

        for (uint256 i = 0; i < strikes.length; i++) {
            ISsovV3.EpochStrikeData memory _temp = ssov.getEpochStrikeData(
                epoch,
                strikes[i]
            );
            strikeTokens[i] = _temp.strikeToken;
        }
    }

    /// @notice Returns total epoch strike deposits array for an epoch
    /// @param epoch target epoch
    /// @param ssov target ssov
    function getTotalEpochStrikeDeposits(uint256 epoch, ISsovV3 ssov)
        external
        view
        returns (uint256[] memory totalEpochStrikeDeposits)
    {
        uint256[] memory strikes = ssov.getEpochStrikes(epoch);
        totalEpochStrikeDeposits = new uint256[](strikes.length);
        for (uint256 i = 0; i < strikes.length; i++) {
            uint256 strike = strikes[i];
            totalEpochStrikeDeposits[i] = ssov
                .getEpochStrikeData(epoch, strike)
                .lastVaultCheckpoint
                .totalCollateral;
        }
    }

    /// @notice Returns total epoch options purchased array for an epoch
    /// @param epoch target epoch
    /// @param ssov target ssov
    function getTotalEpochOptionsPurchased(uint256 epoch, ISsovV3 ssov)
        external
        view
        returns (uint256[] memory _totalEpochOptionsPurchased)
    {
        address[] memory strikeTokens = getEpochStrikeTokens(epoch, ssov);
        _totalEpochOptionsPurchased = new uint256[](strikeTokens.length);
        for (uint256 i = 0; i < strikeTokens.length; i++) {
            _totalEpochOptionsPurchased[i] = IERC20(strikeTokens[i])
                .totalSupply();
        }
    }

    /// @notice Returns the total epoch premium for each strike for an epoch
    /// @param epoch target epoch
    /// @param ssov target ssov
    function getTotalEpochPremium(uint256 epoch, ISsovV3 ssov)
        external
        view
        returns (uint256[] memory _totalEpochPremium)
    {
        uint256[] memory strikes = ssov.getEpochStrikes(epoch);
        _totalEpochPremium = new uint256[](strikes.length);

        uint256 strike;

        for (uint256 i = 0; i < strikes.length; i++) {
            strike = strikes[i];
            ISsovV3.EpochStrikeData memory _temp = ssov.getEpochStrikeData(
                epoch,
                strike
            );
            _totalEpochPremium[i] = _temp
                .lastVaultCheckpoint
                .premiumCollectedCumulative;
        }
    }

    /// @notice Returns the premium & rewards collected for a write position
    /// @param tokenId token id of the write position
    /// @param ssov target ssov
    function getWritePositionValue(uint256 tokenId, ISsovV3 ssov)
        external
        view
        returns (
            uint256 estimatedCollateralUsage,
            uint256 premiumsAccrued,
            uint256[] memory rewardTokenWithdrawAmounts
        )
    {
        (
            uint256 epoch,
            uint256 strike,
            uint256 collateralAmount,
            ISsovV3.VaultCheckpoint memory vaultCheckpoint
        ) = ssov.writePosition(tokenId);

        ISsovV3.EpochStrikeData memory epochStrikeData = ssov
            .getEpochStrikeData(epoch, strike);

        ISsovV3.EpochData memory epochData = ssov.getEpochData(epoch);

        premiumsAccrued = ((collateralAmount *
            (epochStrikeData.lastVaultCheckpoint.premiumDistributionRatio -
                vaultCheckpoint.premiumDistributionRatio)) / 1e18);

        // Get the options usage from the activeCollateralRatio
        uint256 optionsUsage = ssov.isPut()
            ? ((epochStrikeData.lastVaultCheckpoint.activeCollateralRatio -
                vaultCheckpoint.activeCollateralRatio) *
                collateralAmount *
                ssov.getCollateralPrice() *
                1e18) / (ssov.collateralPrecision() * strike * 1e18)
            : ((epochStrikeData.lastVaultCheckpoint.activeCollateralRatio -
                vaultCheckpoint.activeCollateralRatio) *
                collateralAmount *
                epochData.collateralExchangeRate *
                1e18) / (1e26 * ssov.collateralPrecision());

        estimatedCollateralUsage = ssov.calculatePnl(
            ssov.getUnderlyingPrice(),
            strike,
            optionsUsage
        );

        rewardTokenWithdrawAmounts = new uint256[](
            epochData.rewardTokensToDistribute.length
        );

        for (uint256 i = 0; i < rewardTokenWithdrawAmounts.length; i++) {
            rewardTokenWithdrawAmounts[i] +=
                ((epochData.rewardDistributionRatios[i] -
                    vaultCheckpoint.rewardDistributionRatios[i]) *
                    collateralAmount) /
                1e18;
            if (
                epochStrikeData.lastVaultCheckpoint.premiumCollectedCumulative >
                0
            )
                rewardTokenWithdrawAmounts[i] +=
                    (premiumsAccrued *
                        epochStrikeData.rewardsStoredForPremiums[i]) /
                    epochStrikeData
                        .lastVaultCheckpoint
                        .premiumCollectedCumulative;
        }
    }

    /// @notice Returns the tokenIds owned by a wallet of a particular ssov
    /// @param owner wallet owner
    /// @param ssov target ssov
    function walletOfOwner(address owner, ISsovV3 ssov)
        public
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 ownerTokenCount = ssov.balanceOf(owner);
        tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = ssov.tokenOfOwnerByIndex(owner, i);
        }
    }
}

