// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {     JonesLPStrategy,     LPStrategyLib,     IUniswapV2Pair,     I1inchAggregationRouterV4,     ISsovV3,     SsovAdapter,     IERC20,     OneInchZapLib } from "./JonesLPStrategy.sol";
import {IBullLPVault} from "./ILPVault.sol";

contract JonesLPBullStrategy is JonesLPStrategy {
    using SsovAdapter for ISsovV3;

    /**
     * @param _name The name of the strategy
     * @param _oneInch The 1Inch router contract
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
    {}

    /**
     * @notice Inits the strategy by borrowing and taking snapshots
     */
    function initStrategy(uint256[2] calldata _minTokenOutputs) external onlyRole(KEEPER) {
        if (initialTime != 0) {
            revert StrategyAlreadyInitialized();
        }

        _borrow(_minTokenOutputs);

        _afterInit(primary.balanceOf(address(this)), secondary.balanceOf(address(this)));
    }

    /**
     * @notice Executes the configured strategy
     * @param _input Struct that includes:
     * _useForPrimary % of collateral to use to buy  primary options
     * _useForSecondary % of collateral to use to buy secondary options
     * _primaryStrikesOrder The expected order of primary strikes
     * _secondaryStrikesOrder The expected order of secondary strikes
     */
    function execute(StageExecutionInputs memory _input, OneInchZapLib.SwapParams memory _swapParams)
        external
        onlyRole(KEEPER)
    {
        if (initialTime == 0) {
            revert StrategyNotInitialized();
        }

        _notExpired();

        Stage[4] memory currentStages = stages;
        Stage memory currentStage;
        uint256 currentStageIndex;

        // Select the current stage
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

        IERC20 _primary = primary;
        IERC20 _secondary = secondary;

        if (_swapParams.desc.srcToken != address(_secondary) || _swapParams.desc.dstToken != address(_primary)) {
            revert InvalidSwap();
        }

        if (_swapParams.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        uint256[2] memory balances = [primaryBalanceSnapshot, secondaryBalanceSnapshot];

        if (balances[1] > 0) {
            // Buy `secondary` calls and get the new bought percentages
            (, currentStage.usedForSecondary) = LPStrategyLib.buyOptions(
                LPStrategyLib.BuyOptionsInput(
                    secondarySsov,
                    secondarySsovEpoch,
                    secondarySsovEpochExpiry,
                    balances[1],
                    _input.useForSecondary,
                    currentStage.limitsForSecondary,
                    currentStage.usedForSecondary,
                    _input.secondaryStrikesOrder,
                    _input.ignoreITM
                )
            );
        }

        if (balances[0] > 0 || balances[1] > 0) {
            // Swap `secondary` for `primary` and buy `primary` calls
            (, currentStage.usedForSwaps, currentStage.usedForPrimary) = LPStrategyLib.swapAndBuyOptions(
                LPStrategyLib.SwapAndBuyOptionsInput(
                    primarySsov,
                    _secondary,
                    primarySsovEpoch,
                    primarySsovEpochExpiry,
                    balances[0],
                    balances[1],
                    _input.useForPrimary,
                    (_swapParams.desc.amount * basePercentage) / balances[1],
                    _swapParams,
                    currentStage.limitsForPrimary,
                    currentStage.usedForPrimary,
                    _input.primaryStrikesOrder,
                    currentStage.limitForSwaps,
                    currentStage.usedForSwaps,
                    _input.ignoreITM
                )
            );
        }

        _afterExecution(currentStageIndex, currentStage);
    }

    function settle(
        uint256 _minPairTokens,
        address[] calldata _inTokens,
        OneInchZapLib.SwapParams[] calldata _swapParams
    )
        external
        onlyRole(KEEPER)
    {
        if (block.timestamp < primarySsovEpochExpiry || block.timestamp < secondarySsovEpochExpiry) {
            revert SettleBeforeExpiry();
        }

        primarySsov.settleAllStrikesOnEpoch(primarySsovEpoch);
        secondarySsov.settleAllStrikesOnEpoch(secondarySsovEpoch);

        uint256[] memory inTokenAmounts = new uint256[](_inTokens.length);

        for (uint256 i; i < _inTokens.length; i++) {
            inTokenAmounts[i] = IERC20(_inTokens[i]).balanceOf(address(this));
        }

        _repay(_minPairTokens, _inTokens, inTokenAmounts, _swapParams);

        _afterSettlement();
    }

    function borrow(uint256[2] calldata _minTokenOutputs) external onlyRole(MANAGER) {
        _borrow(_minTokenOutputs);
    }

    function repay(
        uint256 _minPairTokens,
        address[] calldata _inTokens,
        uint256[] calldata _inTokenAmounts,
        OneInchZapLib.SwapParams[] calldata _swapParams
    )
        external
        onlyRole(MANAGER)
    {
        _repay(_minPairTokens, _inTokens, _inTokenAmounts, _swapParams);
    }

    function _borrow(uint256[2] calldata _minTokenOutputs) private {
        IBullLPVault lpVault = IBullLPVault(vault);
        if (!lpVault.borrowed()) {
            uint256 borrowed = lpVault.borrow(_minTokenOutputs);

            initialBalanceSnapshot = borrowed;
        }
    }

    function _repay(
        uint256 _minPairTokens,
        address[] memory _inTokens,
        uint256[] memory _inTokenAmounts,
        OneInchZapLib.SwapParams[] calldata _swapParams
    )
        private
    {
        IBullLPVault lpVault = IBullLPVault(vault);

        for (uint256 i; i < _inTokens.length; i++) {
            IERC20(_inTokens[i]).approve(address(lpVault), _inTokenAmounts[i]);
        }

        lpVault.repay(_minPairTokens, _inTokens, _inTokenAmounts, _swapParams);
    }
}

