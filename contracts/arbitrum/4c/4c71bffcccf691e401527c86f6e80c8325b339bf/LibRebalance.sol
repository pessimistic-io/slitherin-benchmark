// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {AggregateVaultStorage} from "./AggregateVaultStorage.sol";
import {FeeEscrow} from "./FeeEscrow.sol";
import {VaultMath} from "./VaultMath.sol";
import {GlpHandler} from "./GlpHandler.sol";
import {ERC20} from "./ERC20.sol";
import {PositionManagerRouter} from "./PositionManagerRouter.sol";
import {GMX_GLP_MANAGER, GMX_GLP_REWARD_ROUTER, GMX_FEE_STAKED_GLP} from "./constants.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {Solarray} from "./Solarray.sol";
import {LibAggregateVaultUtils} from "./LibAggregateVaultUtils.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {UniswapV3SwapManager} from "./UniswapV3SwapManager.sol";

ERC20 constant fsGLP = ERC20(GMX_FEE_STAKED_GLP);
uint256 constant TOTAL_BPS = 10000;

using SafeTransferLib for ERC20;

library LibRebalance {
    event RebalanceGlpPosition(
        uint256[5] vaultGlpAttributionBefore,
        uint256[5] vaultGlpAttributionAfter,
        uint256[5] targetGlpAllocation,
        int256[5] totalVaultGlpDelta,
        int256[5] feeAmounts
    );

    error RebalanceGlpAccountingError();

    function pullFeeAmountsFromEscrow(AggregateVaultStorage.AVStorage storage _avStorage, int256[5] memory _feeAmounts)
        public
    {
        AggregateVaultStorage.VaultState storage vaultState = _avStorage.vaultState;
        FeeEscrow depositFeeEscrow = FeeEscrow(vaultState.depositFeeEscrow);
        FeeEscrow withdrawFeeEscrow = FeeEscrow(vaultState.withdrawalFeeEscrow);

        uint256[5] memory mintFees;
        uint256[5] memory burnFees;

        for (uint256 i = 0; i < _feeAmounts.length; i++) {
            if (_feeAmounts[i] > 0) {
                mintFees[i] = uint256(_feeAmounts[i]);
            } else {
                burnFees[i] = uint256(-_feeAmounts[i]);
            }
        }

        uint256 keeperBps = _avStorage.keeperShareBps;
        address keeper = _avStorage.keeper;
        // reimburse current cycle mint fees from deposit fee escrow and vest the remainder if any
        depositFeeEscrow.pullFeesAndVest(mintFees, keeper, keeperBps);

        // reimburse current cycle burn fees from withdraw fee escrow and vest the remainder if any
        withdrawFeeEscrow.pullFeesAndVest(burnFees, keeper, keeperBps);
    }

    /**
     * @notice Deposits and stakes the given USD allocation in GLP.
     * @dev Has a fallback if liquidity to mint glp from `mintToken` is unavailable. Glp will be minted from the next
     * available token with a swap used on UNIV3.
     * @param glpAllocation The amount of GLP allocation in USD.
     * @param mintToken The token used to mint GLP.
     * @return glpMinted The amount of GLP minted and staked.
     */
    function increaseGlpPosition(
        AggregateVaultStorage.AVStorage storage _avStorage,
        uint256 glpAllocation,
        address mintToken
    ) public returns (uint256, uint256) {
        uint256 usdgMinAmount =
            VaultMath.getSlippageAdjustedAmount(glpAllocation, _avStorage.glpMintBurnSlippageTolerance);
        GlpHandler glpHandler = _avStorage.glpHandler;
        (address derivedMintToken, uint256 minOut) = glpHandler.routeGlpMint(mintToken, glpAllocation, false);

        // if dont need to route through other token
        if (derivedMintToken == mintToken) {
            uint256 tokenAmount = glpHandler.getUsdToToken(glpAllocation, 18, mintToken);
            uint256 feeAdjustedTokenAmount = glpHandler.calculateTokenMintAmount(mintToken, tokenAmount);

            ERC20(mintToken).safeApprove(GMX_GLP_MANAGER, feeAdjustedTokenAmount);
            uint256 glpMinted = IRewardRouterV2(GMX_GLP_REWARD_ROUTER).mintAndStakeGlp(
                mintToken, feeAdjustedTokenAmount, usdgMinAmount, 0
            );

            uint256 feeAmount = feeAdjustedTokenAmount - tokenAmount;
            return (glpMinted, feeAmount);
        }

        uint256 tokenAmount = glpHandler.getUsdToToken(glpAllocation, 18, mintToken);
        uint256 tokenAmountDerivedMintToken = glpHandler.tokenToToken(mintToken, derivedMintToken, tokenAmount);
        uint256 feeAdjustedDerivedMintTokenAmount =
            glpHandler.calculateTokenMintAmount(derivedMintToken, tokenAmountDerivedMintToken);

        AggregateVaultStorage.AVStorage storage __avStorage = _avStorage;
        bytes memory ret = PositionManagerRouter(payable(address(this))).execute(
            address(_avStorage.uniV3SwapManager),
            abi.encodeCall(
                UniswapV3SwapManager.exactOutputSwap,
                (
                    mintToken,
                    derivedMintToken,
                    feeAdjustedDerivedMintTokenAmount,
                    tokenAmount * (TOTAL_BPS + __avStorage.swapToleranceBps) / TOTAL_BPS
                )
            )
        );
        (uint256 amountIn) = abi.decode(ret, (uint256));

        ERC20(derivedMintToken).safeApprove(GMX_GLP_MANAGER, feeAdjustedDerivedMintTokenAmount);
        uint256 glpMinted = IRewardRouterV2(GMX_GLP_REWARD_ROUTER).mintAndStakeGlp(
            mintToken, feeAdjustedDerivedMintTokenAmount, usdgMinAmount, 0
        );
        uint256 feeAmount = amountIn - tokenAmount;
        return (glpMinted, feeAmount);
    }

    /**
     * @notice Reduces the GLP position by converting the given USD allocation to GLP and unstaking the amount with slippage adjustment.
     * @param glpAllocation The amount of GLP allocation in USD.
     * @param tokenOut The token to receive after unstaking GLP.
     * @return glpAmount The amount of GLP unstaked.
     */
    function reduceGlpPosition(
        AggregateVaultStorage.AVStorage storage _avStorage,
        uint256 glpAllocation,
        address tokenOut
    ) public returns (uint256 glpAmount, uint256 feeAmount) {
        GlpHandler glpHandler = _avStorage.glpHandler;
        // usd to glp at current price
        glpAmount = glpHandler.usdToGlp(glpAllocation, 18, false);
        // burn glp amount
        uint256 amountOut =
            IRewardRouterV2(GMX_GLP_REWARD_ROUTER).unstakeAndRedeemGlp(tokenOut, glpAmount, 0, address(this));
        uint256 usdValueTokenOut = glpHandler.getTokenToUsd(tokenOut, amountOut, 18);
        uint256 feeAmountUsd = glpAllocation > usdValueTokenOut ? glpAllocation - usdValueTokenOut : 0;
        feeAmount = glpHandler.getUsdToToken(feeAmountUsd, 18, tokenOut);
    }

    /**
     * @notice Rebalances Glp positions to the _nextGlpAllocation target $ values
     * @dev Internal pnl must be 0 on entry to this function
     * @param _nextGlpAllocation dollar figure for glp allocations
     * @param _glpPrice current glp price
     * @return feeAmounts array of fees collected, -ve means burn fee, +ve means mint fee
     */
    function rebalanceGlpPosition(
        AggregateVaultStorage.AVStorage storage _avStorage,
        uint256[5] memory _nextGlpAllocation,
        uint256 _glpPrice
    ) external returns (int256[5] memory feeAmounts) {
        AggregateVaultStorage.VaultState storage vaultState = _avStorage.vaultState;
        require(vaultState.rebalanceOpen, "rebalancing period not open yet");
        uint256[5] memory glpAlloc = LibAggregateVaultUtils.glpToDollarArray(_avStorage, _glpPrice);

        // find the difference in glp allocations and executable amount
        (, int256[5] memory vaultGlpDeltaAccount) =
            _avStorage.glpRebalanceRouter.netGlpRebalance(glpAlloc, _nextGlpAllocation);
        uint256[5] storage _vaultGlpAttribution = _avStorage.vaultGlpAttribution;
        uint256[5] memory previousVaultGlp = LibAggregateVaultUtils.getVaultsGlpNoPnl(_avStorage); // note must be 0 internal pnl
        AggregateVaultStorage.AssetVaultEntry[5] storage assetVaults = _avStorage.assetVaults;
        uint256[5] memory vaultGlpPartial;
        for (uint256 i = 0; i < 5; i++) {
            if (vaultGlpDeltaAccount[i] > 0) {
                (uint256 glpBurnt, uint256 feeAmount) =
                    reduceGlpPosition(_avStorage, uint256(vaultGlpDeltaAccount[i]), assetVaults[i].token);
                vaultGlpPartial[i] = previousVaultGlp[i] - glpBurnt;
                feeAmounts[i] = -int256(feeAmount);
            } else if (vaultGlpDeltaAccount[i] < 0) {
                (uint256 glpMinted, uint256 feeAmount) =
                    increaseGlpPosition(_avStorage, uint256(-vaultGlpDeltaAccount[i]), assetVaults[i].token);
                vaultGlpPartial[i] = previousVaultGlp[i] + glpMinted;
                feeAmounts[i] = int256(feeAmount);
            } else {
                vaultGlpPartial[i] = previousVaultGlp[i];
            }
        }
        uint256 vaultGlpPartialSum = Solarray.arraySum(vaultGlpPartial);
        {
            uint256 tolerance = _avStorage.glpRebalanceTolerance;
            uint256 totalVaultGlp = fsGLP.balanceOf(address(this));
            uint256 upper = totalVaultGlp * (10000 + tolerance) / 10000;
            uint256 lower = totalVaultGlp * (10000 - tolerance) / 10000;
            if (vaultGlpPartialSum < lower || vaultGlpPartialSum > upper) {
                revert RebalanceGlpAccountingError();
            }
        }
        for (uint256 i = 0; i < 5; ++i) {
            // set floating weights
            _vaultGlpAttribution[i] = (vaultGlpPartial[i] * 1e18) / vaultGlpPartialSum;
        }
        pullFeeAmountsFromEscrow(_avStorage, feeAmounts);
        emit RebalanceGlpPosition(
            previousVaultGlp, vaultGlpPartial, _nextGlpAllocation, vaultGlpDeltaAccount, feeAmounts
        );
    }
}

