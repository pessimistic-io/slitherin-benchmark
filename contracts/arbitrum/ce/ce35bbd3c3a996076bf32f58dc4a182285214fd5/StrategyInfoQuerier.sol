// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./PoolHelper.sol";
import "./IStrategyInfo.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./SafeMath.sol";

/// @dev verified, public contract
contract StrategyInfoQuerier {
    using SafeMath for uint256;

    /// @dev Uniswap-Transaction-related Variable
    function getTransactionDeadlineDuration(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).transactionDeadlineDuration();
    }

    /// @dev get Liquidity-NFT-related Variable
    function getLiquidityNftId(
        address _strategyContract
    ) public view returns (uint256) {
        return IStrategyInfo(_strategyContract).liquidityNftId();
    }

    function getTickSpread(
        address _strategyContract
    ) external view returns (int24) {
        return IStrategyInfo(_strategyContract).tickSpread();
    }

    function getTickEndurance(
        address _strategyContract
    ) external view returns (int24) {
        return IStrategyInfo(_strategyContract).tickEndurance();
    }

    function getTickSpacing(
        address _strategyContract
    ) external view returns (int24) {
        return IStrategyInfo(_strategyContract).tickSpacing();
    }

    /// @dev get Pool-related Variable
    function getPoolAddress(
        address _strategyContract
    ) public view returns (address) {
        return IStrategyInfo(_strategyContract).poolAddress();
    }

    function getPoolFee(
        address _strategyContract
    ) external view returns (uint24) {
        return IStrategyInfo(_strategyContract).poolFee();
    }

    function getToken0Address(
        address _strategyContract
    ) external view returns (address) {
        return IStrategyInfo(_strategyContract).token0Address();
    }

    function getToken1Address(
        address _strategyContract
    ) external view returns (address) {
        return IStrategyInfo(_strategyContract).token1Address();
    }

    /// @dev get Tracker-Token-related Variable
    function getTrackerTokenAddress(
        address _strategyContract
    ) external view returns (address) {
        return IStrategyInfo(_strategyContract).trackerTokenAddress();
    }

    /// @dev get User-Management-related Variable
    function getIsInUserList(
        address _strategyContract,
        address _userAddress
    ) external view returns (bool) {
        return IStrategyInfo(_strategyContract).isInUserList(_userAddress);
    }

    function getUserIndex(
        address _strategyContract,
        address _userAddress
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).userIndex(_userAddress);
    }

    function getAllUsersInUserList(
        address _strategyContract
    ) external view returns (address[] memory userList) {
        return IStrategyInfo(_strategyContract).getAllUsersInUserList();
    }

    /// @dev get User-Share-Management-related Variable
    function getUserShare(
        address _strategyContract,
        address _userAddress
    ) public view returns (uint256 userShare) {
        return IStrategyInfo(_strategyContract).userShare(_userAddress);
    }

    function getTotalUserShare(
        address _strategyContract
    ) public view returns (uint256) {
        return IStrategyInfo(_strategyContract).totalUserShare();
    }

    /// @dev get Reward-Management-related Variable
    function getRewardToken0Amount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).rewardToken0Amount();
    }

    function getRewardToken1Amount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).rewardToken1Amount();
    }

    function getRewardUsdtAmount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).rewardUsdtAmount();
    }

    /// @dev get User-Reward-Management-related Variable
    function getUserUsdtReward(
        address _strategyContract,
        address _userAddress
    ) external view returns (uint256 userUsdtReward) {
        return IStrategyInfo(_strategyContract).userUsdtReward(_userAddress);
    }

    function getTotalUserUsdtReward(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).totalUserUsdtReward();
    }

    /// @dev get Buyback-related Variable
    function getBuyBackToken(
        address _strategyContract
    ) external view returns (address) {
        return IStrategyInfo(_strategyContract).buyBackToken();
    }

    function getBuyBackNumerator(
        address _strategyContract
    ) external view returns (uint24) {
        return IStrategyInfo(_strategyContract).buyBackNumerator();
    }

    /// @dev get Fund-Manager-related Variable
    function getAllFundManagers(
        address _strategyContract
    ) external view returns (IStrategyInfo.FundManager[7] memory fundManagers) {
        return IStrategyInfo(_strategyContract).getAllFundManagers();
    }

    /// @dev get Earn-Loop-Control-related Variable
    function getEarnLoopSegmentSize(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).earnLoopSegmentSize();
    }

    function getEarnLoopDistributedAmount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).earnLoopDistributedAmount();
    }

    function getEarnLoopStartIndex(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).earnLoopStartIndex();
    }

    function getIsEarning(
        address _strategyContract
    ) external view returns (bool) {
        return IStrategyInfo(_strategyContract).isEarning();
    }

    /// @dev get Rescale-related Variable
    function getDustToken0Amount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).dustToken0Amount();
    }

    function getDustToken1Amount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).dustToken1Amount();
    }

    /// @dev get Rescale-Swap-related Variable
    function getMaxToken0ToToken1SwapAmount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).maxToken0ToToken1SwapAmount();
    }

    function getMaxToken1ToToken0SwapAmount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).maxToken1ToToken0SwapAmount();
    }

    function getMinSwapTimeInterval(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).minSwapTimeInterval();
    }

    /// @dev get Rescale-Swap-Pace-Control-related Variable
    function getLastSwapTimestamp(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).lastSwapTimestamp();
    }

    function getRemainingSwapAmount(
        address _strategyContract
    ) external view returns (uint256) {
        return IStrategyInfo(_strategyContract).remainingSwapAmount();
    }

    function getSwapToken0ToToken1(
        address _strategyContract
    ) external view returns (bool) {
        return IStrategyInfo(_strategyContract).swapToken0ToToken1();
    }

    /// @dev get Constant Variable
    function getBuyBackDenominator(
        address _strategyContract
    ) external pure returns (uint24) {
        return IStrategyInfo(_strategyContract).getBuyBackDenominator();
    }

    function getFundManagerProfitDenominator(
        address _strategyContract
    ) external pure returns (uint24) {
        return
            IStrategyInfo(_strategyContract).getFundManagerProfitDenominator();
    }

    function getFarmAddress(
        address _strategyContract
    ) external pure returns (address) {
        return IStrategyInfo(_strategyContract).getFarmAddress();
    }

    function getControllerAddress(
        address _strategyContract
    ) external pure returns (address) {
        return IStrategyInfo(_strategyContract).getControllerAddress();
    }

    function getSwapAmountCalculatorAddress(
        address _strategyContract
    ) external pure returns (address) {
        return
            IStrategyInfo(_strategyContract).getSwapAmountCalculatorAddress();
    }

    function getZapAddress(
        address _strategyContract
    ) external pure returns (address) {
        return IStrategyInfo(_strategyContract).getZapAddress();
    }

    /// @dev get tick info
    function getTickAndPrice(
        address _strategyContract
    ) external view returns (int24, uint256) {
        // get poolAddress
        address poolAddress = getPoolAddress(_strategyContract);

        // get tick
        (, int24 tick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();

        // calculate tokenPrice
        uint256 tokenPriceWithDecimals = getTokenPriceWithDecimalsByPoolAndTick(
            poolAddress,
            tick
        );

        return (tick, tokenPriceWithDecimals);
    }

    function getTickLowerAndPrice(
        address _strategyContract
    ) external view returns (int24, uint256) {
        // get poolAddress
        address poolAddress = getPoolAddress(_strategyContract);

        // get tickLower
        uint256 liquidityNftId = getLiquidityNftId(_strategyContract);
        verifyLiquidityNftIdIsNotZero(liquidityNftId);

        (, , , , , int24 tickLower, , , , , , ) = INonfungiblePositionManager(
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        ).positions(liquidityNftId);

        // calculate tokenPrice
        uint256 tokenPriceWithDecimals = getTokenPriceWithDecimalsByPoolAndTick(
            poolAddress,
            tickLower
        );

        return (tickLower, tokenPriceWithDecimals);
    }

    function getTickUpperAndPrice(
        address _strategyContract
    ) external view returns (int24, uint256) {
        // get poolAddress
        address poolAddress = getPoolAddress(_strategyContract);

        // get tickUpper
        uint256 liquidityNftId = getLiquidityNftId(_strategyContract);
        verifyLiquidityNftIdIsNotZero(liquidityNftId);

        (, , , , , , int24 tickUpper, , , , , ) = INonfungiblePositionManager(
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        ).positions(liquidityNftId);

        // calculate tokenPrice
        uint256 tokenPriceWithDecimals = getTokenPriceWithDecimalsByPoolAndTick(
            poolAddress,
            tickUpper
        );

        return (tickUpper, tokenPriceWithDecimals);
    }

    /// @dev formula explanation
    /*
    [Original formula (without decimal precision)]
    (token1 * (10^decimal1)) / (token0 * (10^decimal0)) = (sqrtPriceX96 / (2^96))^2   
    tokenPrice = token1/token0 = (sqrtPriceX96 / (2^96))^2 * (10^decimal0) / (10^decimal1)

    [Formula with decimal precision & decimal adjustment]
    tokenPriceWithDecimalAdj = tokenPrice * (10^decimalPrecision)
        = (sqrtPriceX96 * (10^decimalPrecision) / (2^96))^2 
            / 10^(decimalPrecision + decimal1 - decimal0)
    */
    function getTokenPriceWithDecimalsByPoolAndTick(
        address poolAddress,
        int24 tick
    ) internal view returns (uint256 tokenPriceWithDecimals) {
        (, , , , , uint256 decimal0, uint256 decimal1) = PoolHelper.getPoolInfo(
            poolAddress
        );

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 decimalPrecision = 18;

        // when decimalPrecision is 18,
        // calculation restriction: 79228162514264337594 <= sqrtPriceX96 <= type(uint160).max
        uint256 scaledPriceX96 = uint256(sqrtPriceX96)
            .mul(10 ** decimalPrecision)
            .div(2 ** 96);
        uint256 tokenPriceWithoutDecimalAdj = scaledPriceX96.mul(
            scaledPriceX96
        );
        uint256 decimalAdj = decimalPrecision.add(decimal1).sub(decimal0);
        uint256 result = tokenPriceWithoutDecimalAdj.div(10 ** decimalAdj);
        require(result > 0, "token price too small");
        tokenPriceWithDecimals = result;
    }

    /// @dev get liquidity token0 token1 balance info
    function getUserLiquidityTokenBalance(
        address _strategyContract,
        address _userAddress
    ) external view returns (uint256 amount0, uint256 amount1) {
        (
            uint160 sqrtPriceX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96,
            uint128 liquidity
        ) = getSqrtPriceAndLiquidityInfo(_strategyContract);

        // calculate user liquidity
        uint256 userShare = getUserShare(_strategyContract, _userAddress);
        uint256 totalShare = getTotalUserShare(_strategyContract);
        uint256 userLiquidity = uint256(liquidity).mul(userShare).div(
            totalShare
        );

        // calculate token amount
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            uint128(userLiquidity)
        );
    }

    function getStrategyLiquidityTokenBalance(
        address _strategyContract
    ) external view returns (uint256 amount0, uint256 amount1) {
        (
            uint160 sqrtPriceX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96,
            uint128 liquidity
        ) = getSqrtPriceAndLiquidityInfo(_strategyContract);

        // calculate token amount
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );
    }

    function getSqrtPriceAndLiquidityInfo(
        address _strategyContract
    )
        internal
        view
        returns (
            uint160 sqrtPriceX96,
            uint160 sqrtRatioAX96,
            uint160 sqrtRatioBX96,
            uint128 liquidity
        )
    {
        // get poolAddress
        address poolAddress = getPoolAddress(_strategyContract);

        // get tick
        (, int24 tick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();

        // get tickUpper & tickLower
        uint256 liquidityNftId = getLiquidityNftId(_strategyContract);
        verifyLiquidityNftIdIsNotZero(liquidityNftId);

        int24 tickLower;
        int24 tickUpper;
        (
            ,
            ,
            ,
            ,
            ,
            tickLower,
            tickUpper,
            liquidity,
            ,
            ,
            ,

        ) = INonfungiblePositionManager(
            Constants.NONFUNGIBLE_POSITION_MANAGER_ADDRESS
        ).positions(liquidityNftId);

        // calculate sqrtPrice
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function verifyLiquidityNftIdIsNotZero(
        uint256 liquidityNftId
    ) internal pure {
        require(
            liquidityNftId != 0,
            "not allow calling when liquidityNftId is 0"
        );
    }
}

