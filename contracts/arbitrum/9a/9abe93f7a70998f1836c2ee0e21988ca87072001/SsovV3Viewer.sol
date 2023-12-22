// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Interfaces
import {ISsovV3} from "./ISsovV3.sol";
import {IERC20} from "./IERC20.sol";

// Structs
import {VaultCheckpoint, WritePosition, EpochStrikeData, EpochData} from "./SsovV3Structs.sol";

contract SsovV3Viewer {
    /// @dev Options token precision
    uint256 internal constant OPTIONS_PRECISION = 1e18;

    /// @dev Strikes, prices and collateral exchange rate is stored in the default precision which is 1e8
    uint256 internal constant DEFAULT_PRECISION = 1e8;

    /// @dev Reward distribution rate precision and any reward token precision
    uint256 internal constant REWARD_PRECISION = 1e18;

    /// @notice Returns the strike token addresses for an epoch
    /// @param epoch target epoch
    /// @param ssov target ssov
    function getEpochStrikeTokens(uint256 epoch, ISsovV3 ssov)
        public
        view
        returns (address[] memory strikeTokens)
    {
        uint256[] memory strikes = ssov.getEpochData(epoch).strikes;
        strikeTokens = new address[](strikes.length);

        for (uint256 i; i < strikes.length; ) {
            EpochStrikeData memory _temp = ssov.getEpochStrikeData(
                epoch,
                strikes[i]
            );
            strikeTokens[i] = _temp.strikeToken;

            unchecked {
                ++i;
            }
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
        uint256[] memory strikes = ssov.getEpochData(epoch).strikes;
        totalEpochStrikeDeposits = new uint256[](strikes.length);
        for (uint256 i; i < strikes.length; ) {
            uint256 strike = strikes[i];
            VaultCheckpoint[] memory checkpoints = getCheckpoints(
                epoch,
                strike,
                ssov
            );

            for (uint256 j; j < checkpoints.length; ) {
                totalEpochStrikeDeposits[i] += checkpoints[j].totalCollateral;

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
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
        for (uint256 i; i < strikeTokens.length; ) {
            _totalEpochOptionsPurchased[i] = IERC20(strikeTokens[i])
                .totalSupply();

            unchecked {
                ++i;
            }
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
        uint256[] memory strikes = ssov.getEpochData(epoch).strikes;
        _totalEpochPremium = new uint256[](strikes.length);

        uint256 strike;

        for (uint256 i; i < strikes.length; ) {
            strike = strikes[i];
            EpochStrikeData memory _temp = ssov.getEpochStrikeData(
                epoch,
                strike
            );
            _totalEpochPremium[i] = _temp.totalPremiums;

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Internal function to get the estimated collateral usage for a checkpoint
    /// @param _checkpoint The checkpoint
    /// @param ssov The ssov
    /// @param strike The strike
    /// @param collateralAmount The collateral amount
    function _getEstimatedCollateralUsage(
        VaultCheckpoint memory _checkpoint,
        ISsovV3 ssov,
        uint256 strike,
        uint256 collateralAmount,
        uint256 collateralExchangeRate
    ) private view returns (uint256) {
        uint256 collateralPrecision = ssov.collateralPrecision();
        uint256 optionsWritten = ssov.isPut()
            ? (_checkpoint.activeCollateral *
                DEFAULT_PRECISION *
                DEFAULT_PRECISION *
                OPTIONS_PRECISION) /
                (strike * collateralPrecision * collateralExchangeRate)
            : (_checkpoint.activeCollateral *
                OPTIONS_PRECISION *
                DEFAULT_PRECISION) /
                (collateralExchangeRate * collateralPrecision);

        return
            ((_checkpoint.totalCollateral -
                ssov.calculatePnl(
                    ssov.getUnderlyingPrice(),
                    strike,
                    optionsWritten,
                    collateralExchangeRate
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

        EpochStrikeData memory epochStrikeData = ssov.getEpochStrikeData(
            epoch,
            strike
        );

        EpochData memory epochData = ssov.getEpochData(epoch);

        // Get the checkpoint
        VaultCheckpoint memory _checkpoint = getCheckpoints(
            epoch,
            strike,
            ssov
        )[checkpointIndex];

        accruedPremium =
            (_checkpoint.accruedPremium * collateralAmount) /
            _checkpoint.totalCollateral;

        // Calculate the withdrawable collateral amount
        estimatedCollateralUsage = _getEstimatedCollateralUsage(
            _checkpoint,
            ssov,
            strike,
            collateralAmount,
            epochData.collateralExchangeRate
        );

        rewardTokenWithdrawAmounts = new uint256[](
            epochData.rewardTokensToDistribute.length
        );

        for (uint256 i; i < rewardTokenWithdrawAmounts.length; ) {
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
        for (uint256 i; i < ownerTokenCount; ) {
            tokenIds[i] = ssov.tokenOfOwnerByIndex(owner, i);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gets the checkpoints of an ssov for an epoch and strike
    /// @param epoch The epoch
    /// @param strike The strike
    /// @param ssov The ssov
    function getCheckpoints(
        uint256 epoch,
        uint256 strike,
        ISsovV3 ssov
    ) public view returns (VaultCheckpoint[] memory checkpoints) {
        uint256 len = ssov.getEpochStrikeCheckpointsLength(epoch, strike);

        checkpoints = new VaultCheckpoint[](len);

        for (uint256 i; i < len; ) {
            checkpoints[i] = ssov.checkpoints(epoch, strike, i);

            unchecked {
                ++i;
            }
        }
    }
}

