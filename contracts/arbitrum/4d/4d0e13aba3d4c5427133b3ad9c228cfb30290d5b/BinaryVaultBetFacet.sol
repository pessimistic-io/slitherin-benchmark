// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";
import {BinaryVaultFacetStorage, IVaultDiamond} from "./BinaryVaultBaseFacet.sol";
import {ICreditToken} from "./ICreditToken.sol";
import {IBinaryVaultBetFacet} from "./IBinaryVaultBetFacet.sol";

contract BinaryVaultBetFacet is
    ReentrancyGuard,
    IBinaryVaultBetFacet,
    IBinaryVaultPluginImpl
{
    using SafeERC20 for IERC20;

    event VaultChangedFromMarket(
        uint256 prevTvl,
        uint256 totalDepositedAmount,
        uint256 watermark
    );

    modifier onlyMarket() {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        require(s.whitelistedMarkets[msg.sender].whitelisted, "ONLY_MARKET");
        _;
    }

    modifier onlyOwner() {
        require(
            IVaultDiamond(address(this)).owner() == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }

    /// @notice Transfer underlying token from user to vault. Update vault state for risk management
    /// @param amount bet amount
    /// @param from originating user
    /// @param endTime round close time
    /// @param position bull if 0, bear if 1 for binary options
    /// @param creditUsed if bet is using credit or not
    /// @param creditTokenIds credit token id from erc1155
    function onPlaceBet(
        uint256 amount,
        address from,
        uint256 endTime,
        uint8 position,
        bool creditUsed,
        uint256[] memory creditTokenIds,
        uint256[] memory creditTokenAmounts,
        address feeWallet,
        uint256 feeAmount
    ) external virtual onlyMarket {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        if (feeAmount > 0) {
            // Send fee amount to fee wallet
            IERC20(s.underlyingTokenAddress).safeTransferFrom(
                from,
                feeWallet,
                feeAmount
            );
        }
        if (!creditUsed) {
            IERC20(s.underlyingTokenAddress).safeTransferFrom(
                from,
                address(this),
                amount
            );
        } else {
            ICreditToken(s.creditToken).burnBatch(
                from,
                creditTokenIds,
                creditTokenAmounts
            );
        }
        BinaryVaultDataType.BetData storage data = s.betData[endTime];

        if (position == 0) {
            data.bullAmount += amount;
        } else {
            data.bearAmount += amount;
        }
    }

    /// @dev This function is used to update total deposited amount from user betting
    /// @param wonAmount amount won from user perspective (lost from vault perspective)
    /// @param loseAmount amount lost from user perspective (won from vault perspective)
    function onRoundExecuted(
        uint256 wonAmount,
        uint256 loseAmount,
        uint256 wonCreditAmount,
        uint256 loseCreditAmount
    ) external virtual override onlyMarket {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 tradingFeeBips = s.config.tradingFee();
        uint256 fee1 = ((wonAmount - wonCreditAmount) * tradingFeeBips) /
            s.config.FEE_BASE();
        uint256 fee2 = ((loseAmount - loseCreditAmount) * tradingFeeBips) /
            s.config.FEE_BASE();

        uint256 tradingFee = fee1 + fee2;

        uint256 depositAmountTotal = wonAmount +
            loseAmount -
            (wonCreditAmount + loseCreditAmount);

        uint256 claimAmountTotal_USDC = ((2 *
            (wonAmount - wonCreditAmount) *
            (s.config.FEE_BASE() - s.config.tradingFee())) /
            s.config.FEE_BASE());

        uint256 claimAmountTotal_Credit = (wonCreditAmount *
            (s.config.FEE_BASE() - s.config.tradingFee())) /
            s.config.FEE_BASE();

        uint256 outAmountTotal = claimAmountTotal_USDC + claimAmountTotal_Credit + tradingFee;

        uint256 prevTvl = s.totalDepositedAmount;

        if (depositAmountTotal > outAmountTotal) {
            s.totalDepositedAmount += depositAmountTotal - outAmountTotal;
        } else {
            uint256 escapeAmount = outAmountTotal - depositAmountTotal;
            s.totalDepositedAmount = s.totalDepositedAmount >= escapeAmount
                ? s.totalDepositedAmount - escapeAmount
                : 0;
        }

        // Update watermark
        if (s.totalDepositedAmount > s.watermark) {
            s.watermark = s.totalDepositedAmount;
        }

        if (tradingFee > 0) {
            IERC20(s.underlyingTokenAddress).safeTransfer(
                s.config.treasuryForReferrals(),
                tradingFee
            );
        }

        emit VaultChangedFromMarket(
            prevTvl,
            s.totalDepositedAmount,
            s.watermark
        );
    }

    /// @notice Claim winning rewards from the vault
    /// In this case, we charge fee from win traders.
    /// @dev Only markets can call this function
    /// @param user Address of winner
    /// @param amount Amount of rewards to claim
    /// @param isRefund whether its refund
    /// @return claim amount
    function claimBettingRewards(
        address user,
        uint256 amount,
        bool isRefund,
        bool creditUsed,
        uint256[] memory creditTokenIds,
        uint256[] memory creditTokenAmounts
    ) external virtual onlyMarket returns (uint256) {
        BinaryVaultFacetStorage.Layout storage s = BinaryVaultFacetStorage
            .layout();

        uint256 claimAmount;
        if (isRefund) {
            claimAmount = amount;
        } else if (creditUsed) {
            claimAmount =
                (amount * (s.config.FEE_BASE() - s.config.tradingFee())) /
                s.config.FEE_BASE();
        } else {
            claimAmount = ((2 *
                amount *
                (s.config.FEE_BASE() - s.config.tradingFee())) /
                s.config.FEE_BASE());
        }

        if (creditUsed && isRefund) {
            ICreditToken(s.creditToken).mintBatch(
                user,
                creditTokenIds,
                creditTokenAmounts
            );
        } else {
            IERC20(s.underlyingTokenAddress).safeTransfer(user, claimAmount);
        }

        return claimAmount;
    }

    function pluginSelectors() private pure returns (bytes4[] memory s) {
        s = new bytes4[](3);
        s[0] = BinaryVaultBetFacet.onPlaceBet.selector;
        s[1] = BinaryVaultBetFacet.onRoundExecuted.selector;
        s[2] = BinaryVaultBetFacet.claimBettingRewards.selector;
    }

    function pluginMetadata()
        external
        pure
        returns (bytes4[] memory selectors, bytes4 interfaceId)
    {
        selectors = pluginSelectors();
        interfaceId = type(IBinaryVaultBetFacet).interfaceId;
    }
}

