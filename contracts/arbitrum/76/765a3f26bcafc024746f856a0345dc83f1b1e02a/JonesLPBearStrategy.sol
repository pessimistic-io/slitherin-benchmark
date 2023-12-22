// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {     JonesLPStrategy,     LPStrategyLib,     IUniswapV2Pair,     I1inchAggregationRouterV4,     ISsovV3,     IERC20,     SsovAdapter,     ZapLib,     OneInchZapLib } from "./JonesLPStrategy.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {IBearLPVault} from "./ILPVault.sol";
import {Curve2PoolAdapter} from "./Curve2PoolAdapter.sol";

contract JonesLPBearStrategy is JonesLPStrategy {
    using SsovAdapter for ISsovV3;
    using Curve2PoolAdapter for IStableSwap;
    using OneInchZapLib for I1inchAggregationRouterV4;

    // Curve 2Crv
    IStableSwap public stableSwap;

    /**
     * @param _name The name of the strategy
     * @param _primarySsov The Ssov related to the primary token
     * @param _secondarySsov The Ssov related to the secondary token
     * @param _primaryToken The primary token on the LP pair
     * @param _secondaryToken The secondary token on the LP pair
     * @param _governor The owner of the contract
     * @param _manager The address allowed to configure the strat and run manual functions
     * @param _keeper The address of the bot that will run the strategy
     */
    constructor(
        bytes32 _name,
        I1inchAggregationRouterV4 _oneInch,
        ISsovV3 _primarySsov,
        ISsovV3 _secondarySsov,
        IERC20 _primaryToken,
        IERC20 _secondaryToken,
        address _governor,
        address _manager,
        address _keeper
    )
        JonesLPStrategy(
            _name,
            _oneInch,
            _primarySsov,
            _secondarySsov,
            _primaryToken,
            _secondaryToken,
            _governor,
            _manager,
            _keeper
        )
    {
        IStableSwap _stableSwap = IStableSwap(OneInchZapLib.crv2);

        address[2] memory stableCoins = [_stableSwap.coins(0), _stableSwap.coins(1)];

        _setWhitelistPair(address(_primaryToken), stableCoins[0], true);
        _setWhitelistPair(address(_primaryToken), stableCoins[1], true);
        _setWhitelistPair(address(_secondaryToken), stableCoins[0], true);
        _setWhitelistPair(address(_secondaryToken), stableCoins[1], true);

        stableSwap = _stableSwap;
    }

    /**
     * @notice Inits the strategy by borrowing, taking snapshots and swapping `secondary` for `2Crv`
     */
    function initStrategy(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        onlyRole(KEEPER)
    {
        if (initialTime != 0) {
            revert StrategyAlreadyInitialized();
        }

        _borrow(_minTokenOutputs, _min2Crv, _intermediateToken, _swapParams);

        uint256 totalCollateral = stableSwap.balanceOf(address(this));
        _afterInit(totalCollateral / 2, totalCollateral - (totalCollateral / 2));
    }

    /**
     * @notice Executes the configured strategy
     * @param _input Struct that includes:
     * _useForPrimary % of collateral to use to buy  primary options
     * _useForSecondary % of collateral to use to buy secondary options
     * _primaryStrikesOrder The expected order of primary strikes
     * _secondaryStrikesOrder The expected order of secondary strikes
     */
    function execute(StageExecutionInputs memory _input) external onlyRole(KEEPER) {
        if (initialTime == 0) {
            revert StrategyNotInitialized();
        }

        _notExpired();

        Stage[4] memory currentStages = stages;
        Stage memory currentStage;
        uint256 currentStageIndex;

        // Select the current strat
        for (uint256 i; i < currentStages.length; i++) {
            currentStage = currentStages[i];
            currentStageIndex = i;

            if (block.timestamp > initialTime + currentStage.duration) {
                // Stage already expired
                continue;
            }

            break;
        }

        if (_input.expectedStageIndex != currentStageIndex) {
            revert ExecutingUnexpectedStage(_input.expectedStageIndex, currentStageIndex);
        }

        uint256 secondaryBalance = secondaryBalanceSnapshot;

        if (secondaryBalance > 0) {
            // Buy `secondary` calls using `secondary` 2Crv balance and get the updated percentages
            (, currentStage.usedForSecondary) = LPStrategyLib.buyOptions(
                LPStrategyLib.BuyOptionsInput(
                    secondarySsov,
                    secondarySsovEpoch,
                    secondarySsovEpochExpiry,
                    secondaryBalance,
                    _input.useForSecondary,
                    currentStage.limitsForSecondary,
                    currentStage.usedForSecondary,
                    _input.secondaryStrikesOrder,
                    _input.ignoreITM
                )
            );
        }

        uint256 primaryBalance = primaryBalanceSnapshot;

        if (primaryBalance > 0) {
            // Buy `primary` calls using `primary` 2Crv balance and get the updated percentages
            (, currentStage.usedForPrimary) = LPStrategyLib.buyOptions(
                LPStrategyLib.BuyOptionsInput(
                    primarySsov,
                    primarySsovEpoch,
                    primarySsovEpochExpiry,
                    primaryBalance,
                    _input.useForPrimary,
                    currentStage.limitsForPrimary,
                    currentStage.usedForPrimary,
                    _input.primaryStrikesOrder,
                    _input.ignoreITM
                )
            );
        }

        _afterExecution(currentStageIndex, currentStage);
    }

    /**
     * @notice Settles the executed strategy
     */
    function settle(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        onlyRole(KEEPER)
    {
        if (block.timestamp < primarySsovEpochExpiry || block.timestamp < secondarySsovEpochExpiry) {
            revert SettleBeforeExpiry();
        }

        primarySsov.settleAllStrikesOnEpoch(primarySsovEpoch);
        secondarySsov.settleAllStrikesOnEpoch(secondarySsovEpoch);

        _repay(_minOutputs, _minLpTokens, _intermediateToken, _swapParams);

        _afterSettlement();
    }

    /**
     * @notice Swaps `depositToken` tokens for `2Crv`
     */
    function zapOutTo2crv(
        uint256 _amount,
        uint256 _token0PairAmount,
        uint256 _token1PairAmount,
        uint256 _min2CrvAmount,
        address _intermediateToken,
        OneInchZapLib.SwapParams calldata _token0Swap,
        OneInchZapLib.SwapParams calldata _token1Swap
    )
        external
        onlyRole(MANAGER)
        returns (uint256)
    {
        if (_token0Swap.desc.dstReceiver != address(this) || _token1Swap.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        return oneInch.zapOutTo2crv(
            address(depositToken),
            _amount,
            _token0PairAmount,
            _token1PairAmount,
            _min2CrvAmount,
            _intermediateToken,
            _token0Swap,
            _token1Swap
        );
    }

    /**
     * @notice Swaps `2Crv` for `depositToken` tokens
     */
    function zapInFrom2Crv(
        OneInchZapLib.SwapParams calldata _swapFromStable,
        OneInchZapLib.SwapParams calldata _toPairTokens,
        uint256 _starting2crv,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _minPairTokens,
        address _intermediateToken
    )
        external
        onlyRole(MANAGER)
        returns (uint256)
    {
        if (_swapFromStable.desc.dstReceiver != address(this) || _toPairTokens.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        return oneInch.zapInFrom2Crv(
            _swapFromStable,
            _toPairTokens,
            address(depositToken),
            _starting2crv,
            _token0Amount,
            _token1Amount,
            _minPairTokens,
            _intermediateToken
        );
    }

    function borrow(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        onlyRole(MANAGER)
    {
        _borrow(_minTokenOutputs, _min2Crv, _intermediateToken, _swapParams);
    }

    function repay(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        onlyRole(MANAGER)
    {
        _repay(_minOutputs, _minLpTokens, _intermediateToken, _swapParams);
    }

    function _borrow(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        private
    {
        IBearLPVault lpVault = IBearLPVault(vault);
        if (!lpVault.borrowed()) {
            uint256[2] memory borrowed = lpVault.borrow(_minTokenOutputs, _min2Crv, _intermediateToken, _swapParams);

            initialBalanceSnapshot = borrowed[0];
        }
    }

    function _repay(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        private
    {
        IBearLPVault lpVault = IBearLPVault(vault);
        IStableSwap twoCrv = stableSwap;

        twoCrv.approve(address(lpVault), twoCrv.balanceOf(address(this)));
        lpVault.repay(_minOutputs, _minLpTokens, _intermediateToken, _swapParams);
    }
}

