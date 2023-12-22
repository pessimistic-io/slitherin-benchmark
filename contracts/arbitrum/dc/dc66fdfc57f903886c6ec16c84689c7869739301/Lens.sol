// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";

import {IQuoterV2} from "./IQuoterV2.sol";
import {IUniswapV3Router} from "./IUniswapV3Router.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {IGmxAdapter} from "./IGmxAdapter.sol";
import {IGmxReader} from "./IGmxReader.sol";
import {IGmxPositionRouter, IGmxRouter} from "./IGmxRouter.sol";
import {IGmxOrderBook, IGmxOrderBookReader} from "./IGmxOrderBook.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IGmxPositionManager} from "./IGmxPositionManager.sol";

import {IBaseVault} from "./IBaseVault.sol";
import {IUsersVault} from "./IUsersVault.sol";
import {ITraderWallet} from "./ITraderWallet.sol";
import {IContractsFactory} from "./IContractsFactory.sol";
import {IDynamicValuation} from "./IDynamicValuation.sol";

contract Lens {
    // uniswap
    IQuoterV2 public constant quoter =
        IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IUniswapV3Factory public constant uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24[4] public uniswapV3Fees = [
        100, // 0.01%
        500, // 0.05%
        3000, // 0.3%
        10000 // 1%
    ];

    // gmx
    IGmxPositionRouter public constant gmxPositionRouter =
        IGmxPositionRouter(0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868);
    IGmxOrderBookReader public constant gmxOrderBookReader =
        IGmxOrderBookReader(0xa27C20A7CF0e1C68C0460706bB674f98F362Bc21);
    IGmxVault public constant gmxVault =
        IGmxVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    address public constant gmxOrderBook =
        0x09f77E8A13De9a35a7231028187e9fD5DB8a2ACB;
    address public constant gmxReader =
        0x22199a49A999c351eF7927602CFB187ec3cae489;
    IGmxPositionManager public constant gmxPositionManager =
        IGmxPositionManager(0x75E42e6f01baf1D6022bEa862A28774a9f8a4A0C);

    /// /// /// /// /// ///
    /// Uniswap
    /// /// /// /// /// ///

    /// @notice Returns the amount out received for a given exact input swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee
    /// @param amountIn The amount of the first token to swap
    /// @return amountOut The amount of the last token that would be received
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function getAmountOut(
        bytes memory path,
        uint256 amountIn
    )
        external
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        return quoter.quoteExactInput(path, amountIn);
    }

    /// @notice Returns the amount in required for a given exact output swap without executing the swap
    /// @param path The path of the swap, i.e. each token pair and the pool fee. Path must be provided in reverse order
    /// @param amountOut The amount of the last token to receive
    /// @return amountIn The amount of first token required to be paid
    /// @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
    /// @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
    /// @return gasEstimate The estimate of the gas that the swap consumes
    function getAmountIn(
        bytes memory path,
        uint256 amountOut
    )
        external
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        return quoter.quoteExactOutput(path, amountOut);
    }

    function getUniswapV3Fees(
        address token1,
        address token2
    ) external view returns (uint24[4] memory resultFees) {
        for (uint8 i; i < 4; i++) {
            uint24 fee = uniswapV3Fees[i];
            address pool = uniswapV3Factory.getPool(token1, token2, fee);

            if (
                pool != address(0) &&
                IERC20(token1).balanceOf(pool) > 0 &&
                IERC20(token2).balanceOf(pool) > 0
            ) {
                resultFees[i] = fee;
            }
        }        
    }

    /// /// /// /// /// ///
    /// GMX
    /// /// /// /// /// ///

    /// increase requests
    function getIncreasePositionRequest(
        bytes32 requestKey
    ) public view returns (IGmxPositionRouter.IncreasePositionRequest memory) {
        return gmxPositionRouter.increasePositionRequests(requestKey);
    }

    /// decrease requests
    function getDecreasePositionRequest(
        bytes32 requestKey
    ) public view returns (IGmxPositionRouter.DecreasePositionRequest memory) {
        return gmxPositionRouter.decreasePositionRequests(requestKey);
    }

    function getIncreasePositionsIndex(
        address account
    ) public view returns (uint256) {
        return gmxPositionRouter.increasePositionsIndex(account);
    }

    function getDecreasePositionsIndex(
        address account
    ) public view returns (uint256) {
        return gmxPositionRouter.decreasePositionsIndex(account);
    }

    function getLatestIncreaseRequest(
        address account
    )
        external
        view
        returns (IGmxPositionRouter.IncreasePositionRequest memory)
    {
        uint256 index = getIncreasePositionsIndex(account);
        bytes32 latestIncreaseKey = gmxPositionRouter.getRequestKey(
            account,
            index
        );
        return getIncreasePositionRequest(latestIncreaseKey);
    }

    function getLatestDecreaseRequest(
        address account
    )
        external
        view
        returns (IGmxPositionRouter.DecreasePositionRequest memory)
    {
        uint256 index = getDecreasePositionsIndex(account);
        bytes32 latestIncreaseKey = gmxPositionRouter.getRequestKey(
            account,
            index
        );
        return getDecreasePositionRequest(latestIncreaseKey);
    }

    function getRequestKey(
        address account,
        uint256 index
    ) external view returns (bytes32) {
        return gmxPositionRouter.getRequestKey(account, index);
    }

    /// @notice Returns current min request execution fee
    function requestMinExecutionFee() external view returns (uint256) {
        return IGmxPositionRouter(gmxPositionRouter).minExecutionFee();
    }

    /// @notice Returns list of positions along specified collateral and index tokens
    /// @param account Wallet or Vault
    /// @param collateralTokens array of collaterals
    /// @param indexTokens array of shorted (or longed) tokens
    /// @param isLong array of position types ('true' for Long position)
    /// @return array with positions current characteristics:
    ///     0 size:         position size in USD (inputAmount * leverage)
    ///     1 collateral:   position collateral in USD
    ///     2 averagePrice: average entry price of the position in USD
    ///     3 entryFundingRate: snapshot of the cumulative funding rate at the time the position was entered
    ///     4 hasRealisedProfit: '1' if the position has a positive realized profit, '0' otherwise
    ///     5 realisedPnl: the realized PnL for the position in USD
    ///     6 lastIncreasedTime: timestamp of the last time the position was increased
    ///     7 hasProfit: 1 if the position is currently in profit, 0 otherwise
    ///     8 delta: amount of current profit or loss of the position in USD
    function getPositions(
        address account,
        address[] memory collateralTokens,
        address[] memory indexTokens,
        bool[] memory isLong
    ) external view returns (uint256[] memory) {
        return
            IGmxReader(gmxReader).getPositions(
                address(gmxVault),
                account,
                collateralTokens,
                indexTokens,
                isLong
            );
    }

    struct ProcessedPosition {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 hasRealisedProfit;
        uint256 realisedPnl;
        uint256 lastIncreasedTime;
        bool hasProfit;
        uint256 delta;
        address collateralToken;
        address indexToken;
        bool isLong;
    }

    /// @notice Returns all current opened positions
    /// @dev Returns all 'short' positions at first
    /// @param account The TraderWallet ir UsersVault address to find all positions
    function getAllPositionsProcessed(
        address account
    ) external view returns (ProcessedPosition[] memory result) {
        address[] memory gmxShortCollaterals = IBaseVault(account)
            .getGmxShortCollaterals();
        address[] memory gmxShortIndexTokens = IBaseVault(account)
            .getGmxShortIndexTokens();
        address[] memory allowedLongTokens = IBaseVault(account)
            .getAllowedTradeTokens();

        uint256 lengthShorts = gmxShortCollaterals.length;
        uint256 lengthLongs = allowedLongTokens.length;
        uint256 totalLength = lengthLongs + lengthShorts;

        if (totalLength == 0) {
            return result;
        }

        result = new ProcessedPosition[](totalLength);

        address[] memory collateralTokens = new address[](totalLength);
        address[] memory indexTokens = new address[](totalLength);
        bool[] memory isLong = new bool[](totalLength);

        // shorts
        for (uint256 i = 0; i < lengthShorts; ++i) {
            collateralTokens[i] = gmxShortCollaterals[i];
            indexTokens[i] = gmxShortIndexTokens[i];
            // isLong[i] = false;  // it is 'false' by default
        }

        // longs
        for (uint256 i = lengthShorts; i < totalLength; ++i) {
            address allowedLongToken = allowedLongTokens[i - lengthShorts];
            collateralTokens[i] = allowedLongToken;
            indexTokens[i] = allowedLongToken;
            isLong[i] = true;
        }

        uint256[] memory positions = IGmxReader(gmxReader).getPositions(
            address(gmxVault),
            account,
            collateralTokens,
            indexTokens,
            isLong
        );

        uint256 index;
        for (uint256 i = 0; i < totalLength; ++i) {
            uint256 positionIndex = i * 9;
            uint256 collateralUSD = positions[positionIndex + 1];
            if (collateralUSD == 0) {
                continue;
            }

            result[index++] = ProcessedPosition({
                size: positions[positionIndex],
                collateral: collateralUSD,
                averagePrice: positions[positionIndex + 2],
                entryFundingRate: positions[positionIndex + 3],
                hasRealisedProfit: positions[positionIndex + 4],
                realisedPnl: positions[positionIndex + 5],
                lastIncreasedTime: positions[positionIndex + 6],
                hasProfit: positions[positionIndex + 7] == 1,
                delta: positions[positionIndex + 8],
                collateralToken: collateralTokens[i],
                indexToken: indexTokens[i],
                isLong: isLong[i]
            });
        }

        if (index != totalLength) {
            assembly {
                mstore(result, index)
            }
        }
    }

    struct AvailableTokenLiquidity {
        uint256 availableLong;
        uint256 availableShort;
    }

    /// @notice Returns current available liquidity for creating position
    /// @param token The token address
    /// @return liquidity Available 'long' and 'short' liquidities in USD scaled to 1e3
    function getAvailableLiquidity(
        address token
    ) external view returns (AvailableTokenLiquidity memory liquidity) {
        liquidity.availableLong =
            gmxPositionManager.maxGlobalLongSizes(token) -
            gmxVault.guaranteedUsd(token);
        liquidity.availableShort =
            gmxPositionManager.maxGlobalShortSizes(token) -
            gmxVault.globalShortSizes(token);
    }

    /// GMX Limit Orders

    /// @notice Returns current account's increase order index
    function increaseOrdersIndex(
        address account
    ) external view returns (uint256) {
        return IGmxOrderBook(gmxOrderBook).increaseOrdersIndex(account);
    }

    /// @notice Returns current account's decrease order index
    function decreaseOrdersIndex(
        address account
    ) external view returns (uint256) {
        return IGmxOrderBook(gmxOrderBook).decreaseOrdersIndex(account);
    }

    /// @notice Returns struct with increase order properties
    function increaseOrder(
        address account,
        uint256 index
    ) external view returns (IGmxOrderBook.IncreaseOrder memory) {
        return IGmxOrderBook(gmxOrderBook).increaseOrders(account, index);
    }

    /// @notice Returns struct with decrease order properties
    function decreaseOrder(
        address account,
        uint256 index
    ) external view returns (IGmxOrderBook.DecreaseOrder memory) {
        return IGmxOrderBook(gmxOrderBook).decreaseOrders(account, index);
    }

    /// @notice Returns current min order execution fee
    function limitOrderMinExecutionFee() external view returns (uint256) {
        return IGmxOrderBook(gmxOrderBook).minExecutionFee();
    }

    function getIncreaseOrders(
        address account,
        uint256[] memory indices
    ) external view returns (uint256[] memory, address[] memory) {
        return
            gmxOrderBookReader.getIncreaseOrders(
                payable(gmxOrderBook),
                account,
                indices
            );
    }

    function getDecreaseOrders(
        address account,
        uint256[] memory indices
    ) external view returns (uint256[] memory, address[] memory) {
        return
            gmxOrderBookReader.getDecreaseOrders(
                payable(gmxOrderBook),
                account,
                indices
            );
    }

    // /// @notice Calculates the max amount of tokenIn that can be swapped
    // /// @param tokenIn The address of input token
    // /// @param tokenOut The address of output token
    // /// @return amountIn Maximum available amount to be swapped
    // function getMaxAmountIn(
    //     address tokenIn,
    //     address tokenOut
    // ) external view returns (uint256 amountIn) {
    //     return IGmxReader(gmxReader).getMaxAmountIn(address(gmxVault), tokenIn, tokenOut);
    // }

    // /// @notice Returns amount out after fees and the fee amount
    // /// @param tokenIn The address of input token
    // /// @param tokenOut The address of output token
    // /// @param amountIn The amount of tokenIn to be swapped
    // /// @return amountOutAfterFees The amount out after fees,
    // /// @return feeAmount The fee amount in terms of tokenOut
    // function getAmountOut(
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn
    // ) external view returns (uint256 amountOutAfterFees, uint256 feeAmount) {
    //     return
    //         IGmxReader(gmxReader).getAmountOut(
    //             address(gmxVault),
    //             tokenIn,
    //             tokenOut,
    //             amountIn
    //         );
    // }

    struct DepositData {
        uint256 amountUSD;
        uint256 sharesToMint;
        uint256 sharePrice;
        uint256 totalRequests;
        uint256 usdDecimals;
    }

    function getDepositData(
        address usersVault
    ) public view returns (DepositData memory result) {
        uint256 pendingDepositAssets = IUsersVault(usersVault)
            .pendingDepositAssets();
        address underlyingTokenAddress = IUsersVault(usersVault)
            .underlyingTokenAddress();

        address contractsFactoryAddress = IUsersVault(usersVault)
            .contractsFactoryAddress();
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();

        result.usdDecimals = IDynamicValuation(dynamicValuationAddress)
            .decimals();

        result.amountUSD = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(underlyingTokenAddress, pendingDepositAssets);

        uint256 currentRound = IUsersVault(usersVault).currentRound();
        if (currentRound == 0) {
            uint256 balance = IERC20(underlyingTokenAddress).balanceOf(
                usersVault
            );

            result.sharesToMint = IDynamicValuation(dynamicValuationAddress)
                .getOraclePrice(underlyingTokenAddress, balance);

            result.sharePrice = 1e18;
        } else {
            uint256 contractValuation = IUsersVault(usersVault)
                .getContractValuation();
            uint256 _totalSupply = IUsersVault(usersVault).totalSupply();

            result.sharePrice = _totalSupply != 0
                ? (contractValuation * 1e18) / _totalSupply
                : 1e18;

            uint256 depositPrice = IDynamicValuation(dynamicValuationAddress)
                .getOraclePrice(underlyingTokenAddress, pendingDepositAssets);

            result.sharesToMint = (depositPrice * 1e18) / result.sharePrice;
        }
    }

    struct WithdrawData {
        uint256 amountUSD;
        uint256 sharesToBurn;
        uint256 sharePrice;
        uint256 totalRequests;
        uint256 usdDecimals;
    }

    function getWithdrawData(
        address usersVault
    ) public view returns (WithdrawData memory result) {
        uint256 pendingWithdrawShares = IUsersVault(usersVault)
            .pendingWithdrawShares();
        address underlyingTokenAddress = IUsersVault(usersVault)
            .underlyingTokenAddress();

        address contractsFactoryAddress = IUsersVault(usersVault)
            .contractsFactoryAddress();
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();

        result.usdDecimals = IDynamicValuation(dynamicValuationAddress)
            .decimals();

        result.sharesToBurn = pendingWithdrawShares;

        uint256 _totalSupply = IUsersVault(usersVault).totalSupply();
        result.sharePrice = _totalSupply != 0
            ? (IUsersVault(usersVault).getContractValuation() * 1e18) /
                _totalSupply
            : 1e18;

        uint256 processedWithdrawAssets = (result.sharePrice *
            pendingWithdrawShares) / 1e18;

        result.amountUSD = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(underlyingTokenAddress, processedWithdrawAssets);
    }

    struct BaseVaultData {
        uint256 totalFundsUSD;
        uint256 unusedFundsUSD;
        uint256 deployedUSD;
        uint256 currentValueUSD;
        int256 returnsUSD;
        int256 returnsPercent;
        uint256 usdDecimals;
    }

    function _getBaseVaultData(
        address baseVault
    ) private view returns (BaseVaultData memory result) {
        address contractsFactoryAddress = IBaseVault(baseVault)
            .contractsFactoryAddress();
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();

        result.totalFundsUSD = IDynamicValuation(dynamicValuationAddress)
            .getDynamicValuation(baseVault);
        result.currentValueUSD = result.totalFundsUSD;

        uint256 afterRoundBalance = IBaseVault(baseVault).afterRoundBalance();
        if (afterRoundBalance != 0) {
            result.returnsPercent =
                int256((result.totalFundsUSD * 1e18) / afterRoundBalance) -
                int256(1e18);
        }

        result.returnsUSD =
            int256(result.totalFundsUSD) -
            int256(IBaseVault(baseVault).afterRoundBalance());

        address underlyingTokenAddress = IBaseVault(baseVault)
            .underlyingTokenAddress();
        uint256 underlyingAmount = IERC20(underlyingTokenAddress).balanceOf(
            baseVault
        );
        result.unusedFundsUSD = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(underlyingTokenAddress, underlyingAmount);

        if (result.totalFundsUSD > result.unusedFundsUSD) {
            result.deployedUSD = result.totalFundsUSD - result.unusedFundsUSD;
        } else {
            result.deployedUSD = 0;
        }

        result.usdDecimals = IDynamicValuation(dynamicValuationAddress)
            .decimals();
    }

    struct UsersVaultData {
        uint256 totalFundsUSD;
        uint256 unusedFundsUSD;
        uint256 deployedUSD;
        uint256 currentValueUSD;
        int256 returnsUSD;
        int256 returnsPercent;
        uint256 totalShares;
        uint256 sharePrice;
        uint256 usdDecimals;
    }

    function getUsersVaultData(
        address usersVault
    ) public view returns (UsersVaultData memory result) {
        BaseVaultData memory baseVaultResult = _getBaseVaultData(usersVault);

        result.totalFundsUSD = baseVaultResult.totalFundsUSD;
        result.unusedFundsUSD = baseVaultResult.unusedFundsUSD;
        result.deployedUSD = baseVaultResult.deployedUSD;
        result.currentValueUSD = baseVaultResult.currentValueUSD;
        result.returnsUSD = baseVaultResult.returnsUSD;
        result.returnsPercent = baseVaultResult.returnsPercent;
        result.usdDecimals = baseVaultResult.usdDecimals;

        address contractsFactoryAddress = IUsersVault(usersVault)
            .contractsFactoryAddress();
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();
        address underlyingTokenAddress = IUsersVault(usersVault)
            .underlyingTokenAddress();

        uint256 oneUnderlyingToken = 10 **
            IERC20Metadata(underlyingTokenAddress).decimals();
        uint256 underlyingPrice = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(underlyingTokenAddress, oneUnderlyingToken);

        uint256 reservedAssets = IUsersVault(usersVault).kunjiFeesAssets() +
            IUsersVault(usersVault).pendingDepositAssets() +
            IUsersVault(usersVault).processedWithdrawAssets();
        uint256 reservedValuation = (reservedAssets * underlyingPrice) /
            oneUnderlyingToken;

        if (result.unusedFundsUSD > reservedValuation) {
            result.unusedFundsUSD -= reservedValuation;
        } else {
            result.unusedFundsUSD = 0;
        }

        if (result.deployedUSD > reservedValuation) {
            result.deployedUSD -= reservedValuation;
        } else {
            result.deployedUSD = 0;
        }

        if (result.totalFundsUSD > reservedValuation) {
            result.totalFundsUSD -= reservedValuation;
        } else {
            result.totalFundsUSD = 0;
        }

        result.totalShares = IUsersVault(usersVault).totalSupply();
        if (result.totalShares != 0 && result.totalFundsUSD != 0) {
            result.sharePrice =
                (result.totalFundsUSD * 1e18) /
                result.totalShares;
        } else {
            result.sharePrice = 1e18;
        }
    }

    struct TraderWalletData {
        uint256 totalFundsUSD;
        uint256 unusedFundsUSD;
        uint256 deployedUSD;
        uint256 currentValueUSD;
        int256 returnsUSD;
        int256 returnsPercent;
        uint256 uvTvUnused;
        uint256 usdDecimals;
    }

    function getTraderWalletData(
        address traderWallet
    ) public view returns (TraderWalletData memory result) {
        BaseVaultData memory baseVaultResult = _getBaseVaultData(traderWallet);

        result.totalFundsUSD = baseVaultResult.totalFundsUSD;
        result.unusedFundsUSD = baseVaultResult.unusedFundsUSD;
        result.deployedUSD = baseVaultResult.deployedUSD;
        result.currentValueUSD = baseVaultResult.currentValueUSD;
        result.returnsUSD = baseVaultResult.returnsUSD;
        result.returnsPercent = baseVaultResult.returnsPercent;
        result.usdDecimals = baseVaultResult.usdDecimals;
    }

    function getDashboardInfo(
        address traderWallet
    )
        external
        view
        returns (
            UsersVaultData memory usersVaultData,
            TraderWalletData memory traderWalletData,
            DepositData memory depositDataRollover,
            WithdrawData memory withdrawDataRollover
        )
    {
        address usersVault = ITraderWallet(traderWallet).vaultAddress();

        usersVaultData = getUsersVaultData(usersVault);
        traderWalletData = getTraderWalletData(traderWallet);

        depositDataRollover = getDepositData(usersVault);
        withdrawDataRollover = getWithdrawData(usersVault);
    }

    struct GmxPrices {
        uint256 tokenMaxPrice;
        uint256 tokenMinPrice;
    }

    /// @notice Returns token prices from gmx oracle
    /// @dev max is used for long positions, min for short
    /// @param token The token address
    /// @return prices Token's max and min prices in USD scaled to 1e30
    function getGmxPrices(
        address token
    ) external view returns (GmxPrices memory prices) {
        prices.tokenMaxPrice = gmxVault.getMaxPrice(token);
        prices.tokenMinPrice = gmxVault.getMinPrice(token);
    }

    /// @notice Returns token price from gmx oracle
    /// @dev used for long positions
    /// @param token The token address
    /// @return Token price in USD scaled to 1e30
    function getGmxMaxPrice(address token) external view returns (uint256) {
        return gmxVault.getMaxPrice(token);
    }

    /// @notice Returns token price from gmx oracle
    /// @dev used for short positions
    /// @param token The token address
    /// @return Token price in USD scaled to 1e30
    function getGmxMinPrice(address token) external view returns (uint256) {
        return gmxVault.getMinPrice(token);
    }

    /// @notice Returns fee amount for opening/increasing/decreasing/closing position
    /// @return ETH amount of required fee
    function getGmxExecutionFee() external view returns (uint256) {
        return gmxPositionRouter.minExecutionFee();
    }

    /// @notice Returns fee amount for executing orders
    /// @return ETH amount of required fee for executing orders
    function getGmxOrderExecutionFee() external view returns (uint256) {
        return IGmxOrderBook(gmxOrderBook).minExecutionFee();
    }
}

