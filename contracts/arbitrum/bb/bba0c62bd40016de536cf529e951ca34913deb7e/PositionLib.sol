// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./PositionInfo.sol";
import "./IPoolAdapter.sol";
import "./ProxyCaller.sol";
import "./ProxyCallerApi.sol";
import "./IPriceOracle.sol";
import "./IMinimaxMain.sol";
import "./IERC20Decimals.sol";
import "./IMarket.sol";
import "./PositionBalanceLib.sol";
import "./PositionExchangeLib.sol";
import "./IPairToken.sol";
import "./Math.sol";
import "./MinimaxAdvanced.sol";
import "./MinimaxBase.sol";

library PositionLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ProxyCallerApi for ProxyCaller;

    enum WithdrawType {
        Manual,
        Liquidation
    }

    uint public constant SwapNoSwapKind = 1;

    uint public constant SwapMarketKind = 2;

    struct SwapMarket {
        bytes hints;
    }

    uint public constant SwapOneInchKind = 3;

    struct SwapOneInch {
        bytes oneInchCallData;
    }

    uint public constant SwapOneInchPairKind = 4;

    struct SwapOneInchPair {
        bytes oneInchCallDataToken0;
        bytes oneInchCallDataToken1;
    }

    struct StakeParams {
        uint inputAmount;
        IERC20Upgradeable inputToken;
        uint stakeAmountMin;
        IERC20Upgradeable stakeToken;
        address stakePool;
        uint maxSlippage;
        uint stopLossPrice;
        uint takeProfitPrice;
        uint swapKind;
        bytes swapArgs;
        uint stakeTokenPrice;
    }

    struct WithdrawParams {
        uint positionIndex;
        uint amount;
        bool amountAll;
        IERC20Upgradeable destinationToken;
        uint destinationTokenAmountMin;
        uint swapKind;
        bytes swapParams;
        uint stakeTokenPrice;
    }

    struct AlterParams {
        uint positionIndex;
        uint amount;
        uint stopLossPrice;
        uint takeProfitPrice;
        uint maxSlippage;
        uint stakeTokenPrice;
    }

    modifier isEnabled(IMinimaxMain main) {
        require(!main.disabled(), "main disabled");
        _;
    }

    function stake(
        IMinimaxMain main,
        ProxyCaller proxy,
        uint positionIndex,
        StakeParams memory params
    ) external isEnabled(main) returns (PositionInfo memory) {
        uint tokenAmount;
        if (params.swapKind == SwapNoSwapKind) {
            tokenAmount = _stakeSimple(params);
        } else if (params.swapKind == SwapMarketKind) {
            SwapMarket memory decoded = abi.decode(params.swapArgs, (SwapMarket));
            tokenAmount = _stakeSwapMarket(main, params, decoded);
        } else if (params.swapKind == SwapOneInchKind) {
            SwapOneInch memory decoded = abi.decode(params.swapArgs, (SwapOneInch));
            tokenAmount = _stakeSwapOneInch(main, params, decoded);
        } else {
            revert("invalid stake kind param");
        }

        main.emitPositionWasCreated(positionIndex, params.stakeToken, params.stakeTokenPrice);

        return _createPosition(main, params, tokenAmount, positionIndex, proxy);
    }

    function _stakeSimple(StakeParams memory params) private returns (uint) {
        params.stakeToken.safeTransferFrom(address(msg.sender), address(this), params.inputAmount);
        return params.inputAmount;
    }

    function _stakeSwapMarket(
        IMinimaxMain main,
        StakeParams memory genericParams,
        SwapMarket memory params
    ) private returns (uint) {
        IMarket market = main.market();
        require(address(market) != address(0), "no market");
        genericParams.inputToken.safeTransferFrom(address(msg.sender), address(this), genericParams.inputAmount);
        genericParams.inputToken.approve(address(market), genericParams.inputAmount);

        return
            market.swap(
                address(genericParams.inputToken),
                address(genericParams.stakeToken),
                genericParams.inputAmount,
                genericParams.stakeAmountMin,
                address(this),
                params.hints
            );
    }

    function makeSwapOneInch(
        uint amount,
        IERC20Upgradeable inputToken,
        address router,
        SwapOneInch memory params
    ) public returns (uint) {
        require(router != address(0), "no 1inch router set");
        // Approve twice more in case of amount fluctuation between estimate and transaction
        inputToken.approve(router, amount * 2);

        (bool success, bytes memory retData) = router.call(params.oneInchCallData);

        ProxyCallerApi.propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
        (uint actualAmount, ) = abi.decode(retData, (uint, uint));
        return actualAmount;
    }

    function _stakeSwapOneInch(
        IMinimaxMain main,
        StakeParams memory genericParams,
        SwapOneInch memory params
    ) private returns (uint) {
        genericParams.inputToken.safeTransferFrom(address(msg.sender), address(this), genericParams.inputAmount);
        address oneInchRouter = main.oneInchRouter();
        return makeSwapOneInch(genericParams.inputAmount, genericParams.inputToken, oneInchRouter, params);
    }

    function _createPosition(
        IMinimaxMain main,
        StakeParams memory params,
        uint tokenAmount,
        uint positionIndex,
        ProxyCaller proxy
    ) private returns (PositionInfo memory) {
        IPoolAdapter adapter = main.getPoolAdapterSafe(params.stakePool);

        require(
            adapter.stakedToken(params.stakePool, abi.encode(params.stakeToken)) == address(params.stakeToken),
            "_createPosition: invalid staking token."
        );

        require(tokenAmount > 0, "_createPosition: zero tokenAmount");

        address[] memory rewardTokens = adapter.rewardTokens(params.stakePool, abi.encode(params.stakeToken));
        IERC20Upgradeable rewardToken = params.stakeToken;
        if (rewardTokens.length > 0) {
            rewardToken = IERC20Upgradeable(rewardTokens[0]);
        }

        uint userFeeAmount = main.getUserFeeAmount(address(msg.sender), tokenAmount);
        uint amountToStake = tokenAmount - userFeeAmount;

        PositionInfo memory position = PositionInfo({
            stakedAmount: amountToStake,
            feeAmount: userFeeAmount,
            stopLossPrice: params.stopLossPrice,
            maxSlippage: params.maxSlippage,
            poolAddress: params.stakePool,
            owner: address(msg.sender),
            callerAddress: proxy,
            closed: false,
            takeProfitPrice: params.takeProfitPrice,
            stakedToken: params.stakeToken,
            rewardToken: rewardToken,
            gelatoLiquidateTaskId: 0
        });

        _proxyDeposit(position, adapter, amountToStake);

        return position;
    }

    function _proxyDeposit(
        PositionInfo memory position,
        IPoolAdapter adapter,
        uint amount
    ) private {
        position.stakedToken.safeTransfer(address(position.callerAddress), amount);
        position.callerAddress.approve(position.stakedToken, position.poolAddress, amount);
        position.callerAddress.deposit(
            adapter,
            position.poolAddress,
            amount,
            abi.encode(position.stakedToken) // pass stakedToken for aave pools
        );
    }

    function alterPositionParams(
        IMinimaxMain main,
        PositionInfo storage position,
        AlterParams memory params
    ) external isEnabled(main) {
        position.stopLossPrice = params.stopLossPrice;
        position.takeProfitPrice = params.takeProfitPrice;
        position.maxSlippage = params.maxSlippage;
        main.emitPositionWasModified(params.positionIndex);

        if (params.amount < position.stakedAmount) {
            uint withdrawAmount = position.stakedAmount - params.amount;
            IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);
            _withdrawToProxy({
                main: main,
                adapter: adapter,
                position: position,
                positionIndex: params.positionIndex,
                amount: withdrawAmount,
                reason: WithdrawType.Manual,
                stakeTokenPrice: params.stakeTokenPrice
            });

            position.callerAddress.transferAll(position.stakedToken, position.owner);
            _withdrawRewards(main, adapter, position, params.positionIndex);
            return;
        }

        if (params.amount > position.stakedAmount) {
            uint depositAmount = params.amount - position.stakedAmount;
            deposit(main, position, params.positionIndex, depositAmount);
        }
    }

    // Emits `PositionsWasModified` always.
    function deposit(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex,
        uint amount
    ) public isEnabled(main) {
        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);

        require(position.owner == address(msg.sender), "deposit: only position owner allowed");
        require(position.closed == false, "deposit: position is closed");

        position.stakedToken.safeTransferFrom(address(msg.sender), address(this), amount);

        uint userFeeAmount = main.getUserFeeAmount(msg.sender, amount);
        uint amountToDeposit = amount - userFeeAmount;

        position.stakedAmount = position.stakedAmount + amountToDeposit;
        position.feeAmount = position.feeAmount + userFeeAmount;

        _proxyDeposit(position, adapter, amountToDeposit);

        _withdrawRewards(main, adapter, position, positionIndex);
        main.emitPositionWasModified(positionIndex);
    }

    function emergencyWithdraw(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex
    ) external isEnabled(main) {
        position.callerAddress.transferAll(position.stakedToken, position.owner);
        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);
        _withdrawRewards(main, adapter, position, positionIndex);
    }

    function estimatePositionStakedTokenPrice(IMinimaxMain minimaxMain, IERC20Upgradeable token)
        public
        view
        returns (uint)
    {
        // Try price oracle first.

        uint8 tokenDecimals = IERC20Decimals(address(token)).decimals();

        IPriceOracle priceOracle = minimaxMain.priceOracles(token);
        if (address(priceOracle) != address(0)) {
            int price = Math.max(0, priceOracle.latestAnswer());
            uint8 oracleDecimals = priceOracle.decimals();
            return adjustDecimals({value: uint(price), valueDecimals: oracleDecimals, wantDecimals: tokenDecimals});
        }

        // We don't have price oracles for `positionStakedToken` -- try to estimate via the Market.

        IMarket market = minimaxMain.market();

        // Market is unavailable, nothing we can do here.
        if (address(market) == address(0)) {
            return 0;
        }

        (bool success, bytes memory encodedEstimateOutResult) = address(market).staticcall(
            abi.encodeCall(market.estimateOut, (address(token), minimaxMain.busdAddress(), 10**tokenDecimals))
        );
        if (!success) {
            return 0;
        }

        (uint price, ) = abi.decode(encodedEstimateOutResult, (uint256, bytes));
        uint8 stablecoinDecimals = IERC20Decimals(minimaxMain.busdAddress()).decimals();

        return adjustDecimals({value: price, valueDecimals: stablecoinDecimals, wantDecimals: tokenDecimals});
    }

    function adjustDecimals(
        uint value,
        uint8 valueDecimals,
        uint8 wantDecimals
    ) private pure returns (uint) {
        if (wantDecimals > valueDecimals) {
            // if
            // value = 3200
            // valueDecimals = 2
            // wantDecimals = 5
            // then
            // result = 3200000
            return value * (10**(wantDecimals - valueDecimals));
        }

        if (valueDecimals > wantDecimals) {
            // if
            // value = 3200
            // valueDecimals = 4
            // wantDecimals = 2
            // then
            // result = 32
            return value / (10**(valueDecimals - wantDecimals));
        }

        return value;
    }

    function estimateLpParts(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex
    ) public isEnabled(main) returns (uint, uint) {
        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);

        _withdrawToProxy({
            main: main,
            adapter: adapter,
            position: position,
            positionIndex: positionIndex,
            amount: 0,
            reason: WithdrawType.Manual,
            stakeTokenPrice: 0
        });

        uint withdrawnBalance = position.stakedToken.balanceOf(address(position.callerAddress));
        position.callerAddress.transferAll(position.stakedToken, address(main));

        IERC20Upgradeable(position.stakedToken).transfer(address(position.stakedToken), withdrawnBalance);

        (uint amount0, uint amount1) = IPairToken(address(position.stakedToken)).burn(address(main));
        return (amount0, amount1);
    }

    function estimateWithdrawnAmount(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex
    ) public isEnabled(main) returns (uint) {
        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);

        _withdrawToProxy({
            main: main,
            adapter: adapter,
            position: position,
            positionIndex: positionIndex,
            amount: 0,
            reason: WithdrawType.Manual,
            stakeTokenPrice: 0
        });

        return position.stakedToken.balanceOf(address(position.callerAddress));
    }

    function isOutsideRange(IMinimaxMain minimaxMain, PositionInfo storage position)
        external
        returns (
            bool isOutsideRange,
            uint256 amountOut,
            bytes memory hints
        )
    {
        if (_isClosed(position)) {
            return (isOutsideRange, amountOut, hints);
        }

        PositionBalanceLib.PositionBalanceV3 memory balance = PositionBalanceLib.getV3(minimaxMain, position);

        uint amountIn = balance.poolStakedAmount;
        (amountOut, hints) = minimaxMain.market().estimateOut(
            address(position.stakedToken),
            minimaxMain.busdAddress(),
            amountIn
        );

        uint8 outDecimals = IERC20Decimals(minimaxMain.busdAddress()).decimals();
        uint8 inDecimals = IERC20Decimals(address(position.stakedToken)).decimals();
        isOutsideRange = PositionExchangeLib.isPriceOutsideRange(
            position,
            amountOut,
            amountIn,
            outDecimals,
            inDecimals
        );
        if (!isOutsideRange) {
            return (isOutsideRange, amountOut, hints);
        }

        // if price oracle exists then double check
        // that price is outside range
        IPriceOracle oracle = minimaxMain.priceOracles(position.stakedToken);
        if (address(oracle) != address(0)) {
            uint oracleMultiplier = 10**oracle.decimals();
            uint oraclePrice = uint(oracle.latestAnswer());
            isOutsideRange = PositionExchangeLib.isPriceOutsideRange(position, oraclePrice, oracleMultiplier, 0, 0);
            if (!isOutsideRange) {
                return (isOutsideRange, amountOut, hints);
            }
        }

        return (isOutsideRange, amountOut, hints);
    }

    function withdraw(
        IMinimaxMain main,
        PositionInfo storage position,
        WithdrawType withdrawType,
        WithdrawParams memory params
    ) public isEnabled(main) {
        if (params.amountAll) {
            require(params.amount == 0);
        } else {
            require(params.amount > 0);
        }

        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);
        _withdrawToProxy({
            main: main,
            adapter: adapter,
            position: position,
            positionIndex: params.positionIndex,
            amount: params.amount,
            reason: withdrawType,
            stakeTokenPrice: params.stakeTokenPrice
        });

        _withdrawRewards(main, adapter, position, params.positionIndex);
        _withdrawStaked(
            main,
            position,
            params.positionIndex,
            params.destinationToken,
            params.destinationTokenAmountMin,
            params.swapKind,
            params.swapParams
        );
    }

    function _withdrawRewards(
        IMinimaxMain main,
        IPoolAdapter adapter,
        PositionInfo storage position,
        uint positionIndex
    ) private {
        address[] memory rewardTokens = adapter.rewardTokens(position.poolAddress, abi.encode(position.stakedToken));
        for (uint i = 0; i < rewardTokens.length; i++) {
            uint amount = position.callerAddress.transferAll(IERC20Upgradeable(rewardTokens[i]), position.owner);
            main.emitRewardTokenWithdraw(positionIndex, rewardTokens[i], amount);
        }
    }

    function _withdrawStaked(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex,
        IERC20Upgradeable destinationToken,
        uint destinationTokenAmountMin,
        uint swapKind,
        bytes memory swapParams
    ) private {
        if (swapKind == SwapNoSwapKind) {
            _withdrawNoSwap(main, position, positionIndex);
        } else if (swapKind == SwapMarketKind) {
            SwapMarket memory decoded = abi.decode(swapParams, (SwapMarket));
            _withdrawMarketSwap(main, position, positionIndex, destinationTokenAmountMin, decoded.hints);
        } else if (swapKind == SwapOneInchKind) {
            SwapOneInch memory decoded = abi.decode(swapParams, (SwapOneInch));
            _withdrawOneInchSingleSwap(main, position, positionIndex, destinationToken, decoded.oneInchCallData);
        } else if (swapKind == SwapOneInchPairKind) {
            SwapOneInchPair memory decoded = abi.decode(swapParams, (SwapOneInchPair));
            _withdrawOneInchPairSwap(
                main,
                position,
                positionIndex,
                address(destinationToken),
                decoded.oneInchCallDataToken0,
                decoded.oneInchCallDataToken0
            );
        } else {
            revert("unexpected withdrawSwapKind");
        }
    }

    function _withdrawNoSwap(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex
    ) private {
        uint amount = position.callerAddress.transferAll(position.stakedToken, position.owner);
        main.emitStakedBaseTokenWithdraw(positionIndex, address(position.stakedToken), amount);
    }

    function _withdrawMarketSwap(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex,
        uint amountOutMin,
        bytes memory marketHints
    ) private {
        IMarket market = main.market();
        uint stakedAmount = IERC20Upgradeable(position.stakedToken).balanceOf(address(position.callerAddress));
        main.emitStakedBaseTokenWithdraw(positionIndex, address(position.stakedToken), stakedAmount);

        position.callerAddress.approve(position.stakedToken, address(market), stakedAmount);

        address withdrawToken = main.busdAddress();
        uint amountOut = position.callerAddress.swap(
            market, // adapter
            address(position.stakedToken), // tokenIn
            withdrawToken, // tokenOut
            stakedAmount, // amountIn
            amountOutMin, // amountOutMin
            position.owner, // to
            marketHints // hints
        );
        main.emitStakedSwapTokenWithdraw(positionIndex, withdrawToken, amountOut);
    }

    function _withdrawOneInchSingleSwap(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex,
        IERC20Upgradeable withdrawToken,
        bytes memory oneInchCallData
    ) private {
        uint stakedAmount = position.callerAddress.transferAll(position.stakedToken, address(this));
        main.emitStakedBaseTokenWithdraw(positionIndex, address(position.stakedToken), stakedAmount);

        address oneInchRouter = main.oneInchRouter();
        uint amountOut = makeSwapOneInch(
            stakedAmount,
            position.stakedToken,
            oneInchRouter,
            SwapOneInch(oneInchCallData)
        );

        withdrawToken.safeTransfer(msg.sender, amountOut);
        main.emitStakedSwapTokenWithdraw(positionIndex, address(withdrawToken), amountOut);
    }

    function _withdrawOneInchPairSwap(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex,
        address withdrawToken,
        bytes memory oneInchCallDataToken0,
        bytes memory oneInchCallDataToken1
    ) private {
        (IERC20Upgradeable token0, uint amount0, IERC20Upgradeable token1, uint amount1) = _burnStaked(
            main,
            position,
            positionIndex
        );
        address oneInchRouter = main.oneInchRouter();
        uint amountOutToken0 = makeSwapOneInch(amount0, token0, oneInchRouter, SwapOneInch(oneInchCallDataToken0));
        uint amountOutToken1 = makeSwapOneInch(amount1, token1, oneInchRouter, SwapOneInch(oneInchCallDataToken1));
        uint amountOut = amountOutToken0 + amountOutToken1;
        IERC20Upgradeable(withdrawToken).safeTransfer(msg.sender, amountOut);
        main.emitStakedSwapTokenWithdraw(positionIndex, withdrawToken, amountOut);
    }

    function _burnStaked(
        IMinimaxMain main,
        PositionInfo storage position,
        uint positionIndex
    )
        private
        returns (
            IERC20Upgradeable token0,
            uint amount0,
            IERC20Upgradeable token1,
            uint amount1
        )
    {
        uint stakedAmount = position.callerAddress.transferAll(position.stakedToken, address(this));
        main.emitStakedBaseTokenWithdraw(positionIndex, address(position.stakedToken), stakedAmount);

        // TODO: when fee of contract is non-zero, then ensure fees from LP-tokens are not burned here
        address lpToken = address(position.stakedToken);
        IERC20Upgradeable(lpToken).transfer(address(lpToken), stakedAmount);
        (amount0, amount1) = IPairToken(lpToken).burn(address(this));
        token0 = IERC20Upgradeable(IPairToken(lpToken).token0());
        token1 = IERC20Upgradeable(IPairToken(lpToken).token1());
        return (token0, amount0, token1, amount1);
    }

    function _isClosed(PositionInfo storage position) private view returns (bool) {
        return position.closed || position.owner == address(0);
    }

    // Withdraws specified amount from pool to proxy
    // If pool balance after withdraw equals zero then position is closed
    // By the end of the function staked and reward tokens are on proxy balance
    function _withdrawToProxy(
        IMinimaxMain main,
        IPoolAdapter adapter,
        PositionInfo storage position,
        uint positionIndex,
        uint amount,
        WithdrawType reason,
        uint stakeTokenPrice
    ) private {
        require(!_isClosed(position), "_withdraw: position closed");

        if (amount == 0) {
            position.callerAddress.withdrawAll(
                adapter,
                position.poolAddress,
                abi.encode(position.stakedToken) // pass stakedToken for aave pools
            );

            if (reason == WithdrawType.Manual) {
                main.emitPositionWasClosed(positionIndex, position.stakedToken, stakeTokenPrice);
                main.closePosition(positionIndex);
                return;
            }

            if (reason == WithdrawType.Liquidation) {
                main.emitPositionWasLiquidated(positionIndex, position.stakedToken, stakeTokenPrice);
                main.closePosition(positionIndex);
                return;
            }

            return;
        }

        position.callerAddress.withdraw(
            adapter,
            position.poolAddress,
            amount,
            abi.encode(position.stakedToken) // pass stakedToken for aave pools
        );

        uint poolBalance = position.callerAddress.stakingBalance(
            adapter,
            position.poolAddress,
            abi.encode(position.stakedToken) // pass stakedToken for aave pools
        );

        if (poolBalance == 0) {
            main.emitPositionWasClosed(positionIndex, position.stakedToken, stakeTokenPrice);
            main.closePosition(positionIndex);
            return;
        }

        main.emitPositionWasModified(positionIndex);

        // When user withdraws partially, stakedAmount should only decrease
        //
        // Consider the following case:
        // position.stakedAmount = 100
        // pool.stakingBalance = 120
        //
        // If user withdraws 10, then:
        // position.stakedAmount = 100
        // pool.stakingBalance = 110
        //
        // If user withdraws 30, then:
        // position.stakedAmount = 90
        // pool.stakingBalance = 90
        //
        if (poolBalance < position.stakedAmount) {
            position.stakedAmount = poolBalance;
        }
    }

    function migratePosition(
        IMinimaxMain main,
        PositionInfo memory position,
        uint positionIndex,
        MinimaxAdvanced advanced,
        MinimaxBase base
    ) external {
        require(position.closed == false);
        // transfer gas tank
        uint gasTankBalance = address(position.callerAddress).balance;
        position.callerAddress.transferNative(address(this), gasTankBalance);

        IPoolAdapter adapter = main.getPoolAdapterSafe(position.poolAddress);
        IToken[] memory rewardTokens;
        address[] memory rewardAddresses = adapter.rewardTokens(position.poolAddress, abi.encode(position.stakedToken));
        // use assembly to force type cast address[] to IToken[]
        assembly {
            rewardTokens := rewardAddresses
        }

        base.migratePosition(
            positionIndex,
            MinimaxBase.Position({
                open: true,
                owner: address(advanced),
                pool: position.poolAddress,
                poolArgs: abi.encode(position.stakedToken),
                proxy: position.callerAddress,
                stakeAmount: position.stakedAmount,
                feeAmount: position.feeAmount,
                stakeToken: IToken(address(position.stakedToken)),
                rewardTokens: rewardTokens
            })
        );

        advanced.migratePosition{value: gasTankBalance}(
            positionIndex,
            MinimaxAdvanced.Position({
                owner: position.owner,
                stopLoss: position.stopLossPrice,
                takeProfit: position.takeProfitPrice,
                maxSlippage: position.maxSlippage,
                gelatoTaskId: 0
            })
        );
    }
}

