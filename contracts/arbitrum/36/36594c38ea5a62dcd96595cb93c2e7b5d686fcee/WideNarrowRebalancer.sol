// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ILiquidityManager} from "./ILiquidityManager.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

import {IAutoRebalancer} from "./IAutoRebalancer.sol";

/// @title Wide-Narrow Auto Rebalancer
/// @author @lance-alot
/// @notice Wide-Narrow Rebalancer for an Algebra Liquidity Manager
contract WideNarrowRebalancer is IAutoRebalancer, AccessControl {
    using SafeERC20 for IERC20;

    /*****************************************************************/
    /******************            EVENTS           ******************/
    /*****************************************************************/

    event SetRangesSettings(uint256 token0InRangesBP_, int24 wideRangeTicksLarge_, int24 narrowRangeTicksLarge_,
        uint256 wideRangeShareOfTokensBP_, uint256 rebalMinPriceDeviationFromOneSideBP_
    );

    event AutoRebalance(int24 currentTick, int24 wideLower, int24 wideUpper, int24 narrowLower, int24 narrowUpper, uint256[4] inMax);
    event RescueERC20(IERC20 token, address to, uint256 amount);

    /*****************************************************************/
    /******************          CONSTANTS         ******************/
    /*****************************************************************/

    bytes32 public constant ADVISOR_ROLE = keccak256("ADVISOR_ROLE");
    ILiquidityManager public immutable LIQUIDITY_MANAGER;

    // Ranges settings
    // Defines how each positions will be setup in terms of ticks
    uint256 public constant PRECISION = 10000;
    uint256 public token0InRangesBP = 5000; // default: 50%
    // Assuming +-1 tick ~= moving price of +-0.01%
    int24 public wideRangeTicksLarge = 12000; // default: -60% (120%*100-token0InRangesBP) | +60% (120%*token0InRangesBP)
    int24 public narrowRangeTicksLarge = 4000; // default: -20% (40%*100-token0InRangesBP) | +20% (40%*token0InRangesBP)

    // default: price must deviate to at least -12% (20*60%) or +12% (20*60%) to allow rebalancing
    uint256 public rebalMinPriceDeviationFromOneSideBP = 6000; // Use the narrower range as reference

    uint256 public wideRangeShareOfTokensBP = 6000; // 60% of all tokens will be used for the wide range

    int24 public lastRebalTickReference = 887273; // init to invalid tick
    int24 public nextRebalMinUpperTick;
    int24 public nextRebalMinLowerTick;


    /*****************************************************************/
    /******************         CONSTRUCTOR         ******************/
    /*****************************************************************/

    constructor(address _admin, address _advisor, address _liquidityManager) {
        require(_admin != address(0), "_admin should be non-zero");
        require(_advisor != address(0), "_advisor should be non-zero");
        require(_liquidityManager != address(0), "_liquidityManager should be non-zero");

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADVISOR_ROLE, _advisor);
        LIQUIDITY_MANAGER = ILiquidityManager(_liquidityManager);
    }

    /********************************************************************/
    /****************** EXTERNAL ADMIN-ONLY FUNCTIONS  ******************/
    /********************************************************************/

    /// @notice Transfer tokens to recipient from the contract
    /// @param token Address of token
    /// @param recipient Recipient Address
    function rescueERC20(IERC20 token, address recipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(recipient != address(0), "RNZ");
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(recipient, amount);
        emit RescueERC20(token, recipient, amount);
    }

    function setRangesSettings(uint256 token0InRangesBP_, int24 wideRangeTicksLarge_, int24 narrowRangeTicksLarge_,
        uint256 wideRangeShareOfTokensBP_, uint256 rebalMinPriceDeviationFromOneSideBP_) external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(token0InRangesBP_ <= PRECISION, "TS");
        require(wideRangeTicksLarge_ > narrowRangeTicksLarge_, "Ranges"); // wide range must be larger than the narrower one
        require(wideRangeShareOfTokensBP_ < PRECISION, "WS"); // wide share must be lower than 100%
        require(rebalMinPriceDeviationFromOneSideBP_ < PRECISION, "RP"); // must be lower than 100%

        token0InRangesBP = token0InRangesBP_;
        wideRangeTicksLarge = wideRangeTicksLarge_;
        narrowRangeTicksLarge = narrowRangeTicksLarge_;
        wideRangeShareOfTokensBP = wideRangeShareOfTokensBP_;
        rebalMinPriceDeviationFromOneSideBP = rebalMinPriceDeviationFromOneSideBP_;
        emit SetRangesSettings(token0InRangesBP, wideRangeTicksLarge, narrowRangeTicksLarge, wideRangeShareOfTokensBP, rebalMinPriceDeviationFromOneSideBP);
    }

    /// @notice auto rebalance the pool via liquidity manager
    /// @param  outMin min amount0,1 returned for shares of liq
    function autoRebalance(uint256[4] calldata outMin) external onlyRole(ADVISOR_ROLE)
        returns (int24 narrowLower, int24 narrowUpper, int24 wideLower, int24 wideUpper)
    {
        (narrowLower, narrowUpper, wideLower, wideUpper) = _autoRebalance(outMin);
    }

    function swapUnusedAndCompound(IERC20 tokenToSwap, uint256 amountIn,
        uint256 amountOutMin, uint160 limitSqrtPrice, uint256[4] calldata inMax) external onlyRole(ADVISOR_ROLE)
    {
        require(address(tokenToSwap) == address(LIQUIDITY_MANAGER.token0()) || address(tokenToSwap) == address(LIQUIDITY_MANAGER.token1()), "TTS"); // Invalid token

        (, uint256 base0BeforeSwap, uint256 base1BeforeSwap) = LIQUIDITY_MANAGER.getBasePosition();
        (, uint256 limit0BeforeSwap, uint256 limit1BeforeSwap) = LIQUIDITY_MANAGER.getLimitPosition();

        LIQUIDITY_MANAGER.collectAllFees();
        LIQUIDITY_MANAGER.swapToken(tokenToSwap, amountIn, amountOutMin, limitSqrtPrice);
        _compound(inMax); // compound swapped tokens into existing positions

        (, uint256 base0, uint256 base1) = LIQUIDITY_MANAGER.getBasePosition();
        (, uint256 limit0, uint256 limit1) = LIQUIDITY_MANAGER.getLimitPosition();

        require(base0BeforeSwap + limit0BeforeSwap < base0 + limit0 && base1BeforeSwap + limit1BeforeSwap < base1 + limit1, "IS"); // Inefficient swap
    }

    /// @notice compound pending fees
    function compound(uint256[4] calldata inMax) external onlyRole(ADVISOR_ROLE) {
        _compound(inMax);
    }

    /********************************************************************/
    /******************       INTERNAL FUNCTIONS       ******************/
    /********************************************************************/

    function _autoRebalance(uint256[4] calldata outMin) internal returns (
        int24 narrowLower, int24 narrowUpper, int24 wideLower, int24 wideUpper
    ){

        int24 currentTick = LIQUIDITY_MANAGER.getCurrentTick();
        require(lastRebalTickReference == 887273 || _isTickOverRebalanceThreshold(currentTick), "R");

        (narrowLower, narrowUpper, wideLower, wideUpper, lastRebalTickReference,
            nextRebalMinLowerTick, nextRebalMinUpperTick) = _getRangeTicksForCurrentTick(currentTick);

        LIQUIDITY_MANAGER.collectAllFees();
        (uint256 totalAvailableToken0, uint256 totalAvailableToken1) = LIQUIDITY_MANAGER.getTotalAmounts();
        uint256 wideToken0MaxAmount = totalAvailableToken0 * wideRangeShareOfTokensBP / PRECISION;
        uint256 wideToken1MaxAmount = totalAvailableToken1 * wideRangeShareOfTokensBP / PRECISION;

        // see how much liquidity we could get at the wide range 
        uint128 maxWideliq = _liquidityForAmounts(wideLower, wideUpper, wideToken0MaxAmount, totalAvailableToken1);
        (uint256 maxWide0, uint256 maxWide1) = _amountsForLiquidity(wideLower, wideUpper, maxWideliq);
        if(maxWide1 > wideToken1MaxAmount) {
            maxWideliq = _liquidityForAmounts(wideLower, wideUpper, totalAvailableToken0, wideToken1MaxAmount);
            (maxWide0, maxWide1) = _amountsForLiquidity(wideLower, wideUpper, maxWideliq);
        }

        int24[4] memory ranges;
        ranges[0] = wideLower;
        ranges[1] = wideUpper;
        ranges[2] = narrowLower;
        ranges[3] = narrowUpper;

        uint256[4] memory inMax;
        inMax[0] = maxWide0;
        inMax[1] = maxWide1;
        inMax[2] = type(uint256).max;
        inMax[3] = type(uint256).max;

        uint256[4] memory inMin;
        LIQUIDITY_MANAGER.rebalance(ranges, inMax, inMin, outMin);

        emit AutoRebalance(currentTick, wideLower, wideUpper, narrowLower, narrowUpper, inMax);
    }

    function _compound(uint256[4] calldata inMax) internal {
        uint256[4] memory inMin;
        LIQUIDITY_MANAGER.compound(inMax, inMin);
        emit Compound(inMax);
    }

    /// @dev returns true if the current price is more than 20% away from the last rebalance price
    function _isTickOverRebalanceThreshold(int24 tick) internal view returns (bool) {
        return tick < nextRebalMinLowerTick || tick > nextRebalMinUpperTick;
    }

    function _liquidityForAmounts(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) internal view returns (uint128) {
        (uint160 sqrtRatioX96, , , , , , ,) = LIQUIDITY_MANAGER.pool().globalState();
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), amount0, amount1
        );
    }

    function _amountsForLiquidity(int24 tickLower, int24 tickUpper, uint256 liq) internal view returns (uint256, uint256){
        (uint160 sqrtRatioX96, , , , , , ,) = LIQUIDITY_MANAGER.pool().globalState();
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(liq)
        );
    }

    function _getRangeTicksForCurrentTick(int24 currentTick) internal view returns (
        int24 narrowLower, int24 narrowUpper, int24 wideLower, int24 wideUpper, int24 currentTickAdjusted,
        int24 nextRebalMinLowerTick_, int24 nextRebalMinUpperTick_
    ){

        int24 tickSpacing = LIQUIDITY_MANAGER.tickSpacing();

        // check compatibility with active tickSpacing
        require(wideRangeTicksLarge * 2 > tickSpacing * 2 && narrowRangeTicksLarge * 2 > tickSpacing, "invalid settings");

        // find the closest tick divisible by tickSpacing
        currentTickAdjusted = currentTick - (currentTick % tickSpacing);
        uint256 tickSpacingUint = uint256(uint24(tickSpacing));

        uint256 wideUpperTicksAmount = uint256(uint24(wideRangeTicksLarge)) * token0InRangesBP / PRECISION;
        wideUpperTicksAmount = (wideUpperTicksAmount / tickSpacingUint) * tickSpacingUint; // Adjust depending of tickSpacing
        uint256 wideLowerTicksAmount = uint256(uint24(wideRangeTicksLarge)) * (PRECISION - token0InRangesBP) / PRECISION;
        wideLowerTicksAmount = (wideLowerTicksAmount / tickSpacingUint) * tickSpacingUint; // Adjust depending of tickSpacing

        uint256 narrowUpperTicksAmount = uint256(uint24(narrowRangeTicksLarge)) * token0InRangesBP / PRECISION;
        narrowUpperTicksAmount = (narrowUpperTicksAmount / tickSpacingUint) * tickSpacingUint; // Adjust depending of tickSpacing
        uint256 narrowLowerTicksAmount = uint256(uint24(narrowRangeTicksLarge)) * (PRECISION - token0InRangesBP) / PRECISION;
        narrowLowerTicksAmount = (narrowLowerTicksAmount / tickSpacingUint) * tickSpacingUint; // Adjust depending of tickSpacing

        wideUpper = currentTickAdjusted + int24(int256(wideUpperTicksAmount));
        wideLower = currentTickAdjusted - int24(int256(wideLowerTicksAmount));

        narrowUpper = currentTickAdjusted + int24(int256(narrowUpperTicksAmount));
        narrowLower = currentTickAdjusted - int24(int256(narrowLowerTicksAmount));

        uint256 nextRebalMinUpperTickAmount = narrowUpperTicksAmount * rebalMinPriceDeviationFromOneSideBP / PRECISION;
        uint256 nextRebalMinLowerTickAmount = narrowLowerTicksAmount * rebalMinPriceDeviationFromOneSideBP / PRECISION;
        nextRebalMinUpperTick_ = currentTickAdjusted + int24(int256(nextRebalMinUpperTickAmount));
        nextRebalMinLowerTick_ = currentTickAdjusted - int24(int256(nextRebalMinLowerTickAmount));
    }
}

