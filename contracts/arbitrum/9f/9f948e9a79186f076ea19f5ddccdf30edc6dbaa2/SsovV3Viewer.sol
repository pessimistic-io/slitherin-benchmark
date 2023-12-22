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
            ISsovV3.VaultCheckpoint[] memory checkpoints = ssov.getCheckpoints(
                epoch,
                strike
            );
            for (uint256 j = 0; j < checkpoints.length; j++) {
                totalEpochStrikeDeposits[i] += checkpoints[j].totalCollateral;
            }
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
            _totalEpochPremium[i] = _temp.totalPremiums;
        }
    }

    function _getEstimatedCollateralUsage(
        ISsovV3.VaultCheckpoint memory _checkpoint,
        ISsovV3 ssov,
        uint256 strike,
        uint256 collateralAmount
    ) private view returns (uint256) {
        return
            ((_checkpoint.totalCollateral -
                ssov.calculatePnl(
                    ssov.getUnderlyingPrice(),
                    strike,
                    ssov.isPut()
                        ? (_checkpoint.activeCollateral * 1e8) / strike
                        : _checkpoint.activeCollateral
                )) * collateralAmount) / _checkpoint.totalCollateral;
    }

    /// @notice Returns the premium & rewards collected for a write position
    /// @param tokenId token id of the write position
    /// @param ssov target ssov
    function getWritePositionValue(uint256 tokenId, ISsovV3 ssov)
        external
        view
        returns (
            uint256 estimatedCollateralUsage,
            uint256 accruedPremium,
            uint256[] memory rewardTokenWithdrawAmounts
        )
    {
        (
            uint256 epoch,
            uint256 strike,
            uint256 collateralAmount,
            uint256 checkpointIndex,
            uint256[] memory rewardDistributionRatios
        ) = ssov.writePosition(tokenId);

        ISsovV3.EpochStrikeData memory epochStrikeData = ssov
            .getEpochStrikeData(epoch, strike);

        ISsovV3.EpochData memory epochData = ssov.getEpochData(epoch);

        // Get the checkpoint
        ISsovV3.VaultCheckpoint memory _checkpoint = ssov.getCheckpoints(
            epoch,
            strike
        )[checkpointIndex];

        accruedPremium =
            (_checkpoint.accruedPremium * collateralAmount) /
            _checkpoint.totalCollateral;

        // Calculate the withdrawable collateral amount
        estimatedCollateralUsage = _getEstimatedCollateralUsage(
            _checkpoint,
            ssov,
            strike,
            collateralAmount
        );

        rewardTokenWithdrawAmounts = new uint256[](
            epochData.rewardTokensToDistribute.length
        );

        for (uint256 i = 0; i < rewardTokenWithdrawAmounts.length; ) {
            rewardTokenWithdrawAmounts[i] +=
                ((epochData.rewardDistributionRatios[i] -
                    rewardDistributionRatios[i]) * collateralAmount) /
                1e18;
            if (epochStrikeData.totalPremiums > 0)
                rewardTokenWithdrawAmounts[i] +=
                    (accruedPremium *
                        epochStrikeData.rewardStoredForPremiums[i]) /
                    epochStrikeData.totalPremiums;
            unchecked {
                i++;
            }
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

