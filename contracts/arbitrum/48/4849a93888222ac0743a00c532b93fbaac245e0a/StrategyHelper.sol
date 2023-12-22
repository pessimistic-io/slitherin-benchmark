// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

/**
 * @title Dopex V2 Automated Liquidity Management for Arbitrum STIP Rewards
 * @author Orange Finance
 * @notice This contract is tailored for optimizing liquidity positions within the Dopex V2 protocol
 * on the Arbitrum network, specifically for the STIP rewards program. It automatically adjusts liquidity
 * within a range of ±2.5% from the current market price, ensuring eligibility for STIP rewards while aiming
 * to maximize returns and minimize risks associated with price volatility.
 *
 * Key Features:
 * 1. Targeted Liquidity Range: Maintains liquidity positions within ±2.5% of the current market price,
 *    aligning with the requirements of the Dopex V2 STIP rewards program.
 * 2. Automated Adjustments: Reacts to market changes and automatically adjusts positions to stay within
 *    the optimal range for rewards and risk mitigation.
 * 3. Enhanced Yield Potential: By focusing on a narrow price range, the strategy aims to capture higher
 *    trading fees and STIP rewards.
 *
 * Risk:
 * - This strategy keep traking current price with narrow range that potentially cause huge divergence loss depending on market condition.
 *
 * @dev some internal calls have "this." prefix, but this is for testing that utlize mockCall powered by Foundry.
 *       https://github.com/foundry-rs/foundry/issues/432
 */

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {OracleLibrary} from "./OracleLibrary.sol";
import {TickMath} from "./TickMath.sol";

import {IERC20} from "./IERC20.sol";
import {IERC1155Receiver} from "./ERC1155Receiver.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {SafeCast} from "./SafeCast.sol";
import {AccessControlEnumerable} from "./AccessControlEnumerable.sol";
import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {IUniswapV3SingleTickLiquidityHandler} from "./IUniswapV3SingleTickLiquidityHandler.sol";
import {UniswapV3SingleTickLiquidityLib} from "./UniswapV3SingleTickLiquidityLib.sol";
import {AutomatorUniswapV3PoolLib} from "./AutomatorUniswapV3PoolLib.sol";
import {IDopexV2PositionManager} from "./IDopexV2PositionManager.sol";

import {IAutomator} from "./IAutomator.sol";

contract StrategyHelper {
    using FixedPointMathLib for uint256;
    using AutomatorUniswapV3PoolLib for IUniswapV3Pool;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using TickMath for int24;

    IAutomator public immutable automator;
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable asset;
    IERC20 public immutable counterAsset;
    bool public immutable reversed;

    int24 public immutable poolTickSpacing;
    int24 public constant tickRange = 25; //2.5% when tickSpacing is 10
    uint128 private constant LIQUIDITY_UNIT = 1000000000; //magic number

    //buffer for swap
    uint256 private constant SWAP_BUFFER_BPS = 9900;
    uint256 private constant SWAP_BUFFER_DIVISOR = 10000;

    struct AssetInfo {
        uint256 assets;
        uint256 counterAssets;
    }

    struct Categories {
        uint256 burn;
        uint256 mint;
        uint256 stay;
    }

    constructor(IAutomator automator_) {
        automator = automator_;
        pool = IUniswapV3Pool(automator_.pool());
        poolTickSpacing = pool.tickSpacing();
        asset = automator.asset();
        counterAsset = automator.counterAsset();
        reversed = address(asset) < address(counterAsset) ? false : true;
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    MAIN FUNCTION
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/
    /**
     * @notice Three type of rebalance() strategy.
     * 1. checkLiquidizePooledAssets: All Tick Operation. Run not often.
     * 2. checkBurnOuterLiquidity: Partial Tick Operation. Run very often.
     */

    /**
     * @notice put the pooled deposits into liquidity. This is a operation across all activeTick, so it does track the current tick and adjust the liquidity as well.
     * @dev All ticks operation.
     */
    function checkLiquidizePooledAssets() external view returns (bool, bytes memory) {
        //1. Get rebalance ticks
        (int24[] memory _burnTicks, int24[] memory _mintTicks, int24[] memory _stayTicks) = this.getRebalanceTicks(); //"this." is used for testing purpose. detail is above.

        //2. Get liquidity and asset information
        (IAutomator.RebalanceTickInfo[] memory _burnTicksInfo, , uint256 _totalUnburnableValueInAssets) = this
            .getBurnableTicksInfo(_burnTicks);

        IAutomator.RebalanceTickInfo[] memory _stayTicksInfo = this.getActiveTicksInfo(_stayTicks);

        uint256 _distributableAssets = automator.totalAssets() - _totalUnburnableValueInAssets;
        _distributableAssets = (_distributableAssets * SWAP_BUFFER_BPS) / SWAP_BUFFER_DIVISOR; //make buffer for swap fee. (automator swaps token by exactOutputSingle, so fees are only taken from input)

        //3. Calculate target liquidity amount for every tick
        uint256 _assetsPerLiquidityUnit = this.getAssetsPerLiquidityUnit(_mintTicks) +
            this.getAssetsPerLiquidityUnit(_stayTicks);
        uint128 _targetLiquidity = uint128((_distributableAssets * LIQUIDITY_UNIT) / _assetsPerLiquidityUnit);

        //Mint info (new ticks, so mint liquidity =  _targetLiquidity)
        IAutomator.RebalanceTickInfo[] memory _mintTicksInfo = new IAutomator.RebalanceTickInfo[](_mintTicks.length);
        for (uint256 i; i < _mintTicks.length; i++) {
            _mintTicksInfo[i] = IAutomator.RebalanceTickInfo(_mintTicks[i], _targetLiquidity);
        }

        //Classify the stay ticks
        (
            IAutomator.RebalanceTickInfo[] memory newMintTicksInfo,
            IAutomator.RebalanceTickInfo[] memory newBurnTicksInfo
        ) = this.classifyStayTicks(_mintTicksInfo, _burnTicksInfo, _stayTicksInfo, _targetLiquidity);

        //Prepare Gelato package
        IAutomator.RebalanceSwapParams memory _swapParams = automator.calculateRebalanceSwapParamsInRebalance(
            newMintTicksInfo,
            newBurnTicksInfo
        );

        bytes memory execPayload = abi.encodeWithSelector(
            automator.rebalance.selector,
            newMintTicksInfo,
            newBurnTicksInfo,
            _swapParams
        );
        return (true, execPayload);
    }

    /**
     * @notice Monitor burnable liquidity by Gelato, and burn whenever it become possible to do so.
     */
    function checkBurnOuterLiquidity() external view returns (bool, bytes memory) {
        //1. Get Burn Ticks
        (int24[] memory _burnTicks, , ) = this.getRebalanceTicks();

        //2. get burnable liquidity
        (IAutomator.RebalanceTickInfo[] memory _burnTicksInfo, , ) = this.getBurnableTicksInfo(_burnTicks); //"this." is used for testing purpose. detail is above.

        if (_burnTicksInfo.length != 0) {
            //Prepare Gelato package
            IAutomator.RebalanceTickInfo[] memory _mintTicksInfo; //0
            IAutomator.RebalanceSwapParams memory _swapParams = automator.calculateRebalanceSwapParamsInRebalance(
                _mintTicksInfo,
                _burnTicksInfo
            );
            bytes memory execPayload = abi.encodeWithSelector(
                automator.rebalance.selector,
                _mintTicksInfo,
                _burnTicksInfo,
                _swapParams
            );
            return (true, execPayload);
        } else {
            return (false, bytes("no burnable tick"));
        }
    }

    /*///////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    Utility
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Determines the ticks to be burned, minted, or to stay as is for rebalancing.
     * @dev This function first retrieves the current active ticks from the Automator contract. It then calculates
     *      the current lower tick based on the current tick of the pool. Using this lower tick, it generates
     *      the target ticks for rebalancing. The function then categorizes these ticks into three categories:
     *      - Ticks to be burned (`_burnTicks`).
     *      - Ticks to be minted (`_mintTicks`).
     *      - Ticks that will stay as is (`_stayTicks`).
     *      This categorization is done based on the comparison of active ticks and target ticks. After categorizing,
     *      it validates the mint ticks to ensure they meet creteria by validateMintTicks().
     * @return _burnTicks An array of tick indexes that should be burned during rebalancing.
     * @return _mintTicks An array of tick indexes that should be minted during rebalancing.
     * @return _stayTicks An array of tick indexes that do not require any action during rebalancing.
     */
    function getRebalanceTicks()
        public
        view
        returns (int24[] memory _burnTicks, int24[] memory _mintTicks, int24[] memory _stayTicks)
    {
        //currentLT should be removed from both ticks.
        int24[] memory _activeTicks = removeCurrentTick(automator.getActiveTicks());
        int24[] memory _targetTicks = getTargetTicks();

        (_burnTicks, _mintTicks, _stayTicks) = analyzeTickChanges(_activeTicks, _targetTicks);
        _mintTicks = validateMintTicks(_mintTicks);
    }

    /**
     * @notice Generates an array of target ticks for rebalancing, +-2.5% of currentPrice without including current tick.
     * @return targetTicks An array of tick indices calculated around `_currentLT`, excluding `_currentLT` itself.
     */
    function getTargetTicks() public view returns (int24[] memory) {
        int24 _currentLT = this.getCurrentLT(pool.currentTick());
        int24[] memory targetTicks = new int24[](uint256(uint24(tickRange * 2)));
        int24 lowerTickStart = _currentLT - (tickRange * poolTickSpacing);

        int24 tick = lowerTickStart;
        for (uint256 i; i < targetTicks.length; ) {
            if (tick == _currentLT) {
                tick += poolTickSpacing;
                continue;
            }
            targetTicks[i] = tick;
            tick += poolTickSpacing;
            i++;
        }

        return targetTicks;
    }

    /**
     * @notice Calculates the lower tick closest to the current tick, adjusted by the pool's tick spacing.
     * @dev This function calculates the lower tick (`_currentLowerTick`) for a given current tick (`_currentTick`).
     *      The calculation is based on the tick spacing of the pool. For positive ticks, it rounds down to the
     *      nearest lower tick. For ticks exactly on a spacing boundary, it classifies the current tick as a lower
     *      tick accourding to the . For negative ticks, the calculation behaves similar to the `ceil()` function rather than `floor()`.
     *      Therefore, an adjustment is made to ensure the result is a valid lower tick.
     * @param _currentTick The current tick of the pool.
     * @return _currentLowerTick The calculated lower tick based on the current tick and the pool's tick spacing.
     */
    function getCurrentLT(int24 _currentTick) public view returns (int24 _currentLowerTick) {
        _currentLowerTick = (_currentTick / poolTickSpacing) * poolTickSpacing;

        if (_currentTick < 0 && _currentTick % poolTickSpacing != 0) {
            _currentLowerTick -= poolTickSpacing;
        }
    }

    /**
     *@notice Generates burn, mint, and stay ticks for rebalancing orders.
     * This function compares two arrays of ticks (activeTicks and targetTicks) and
     * categorizes their elements into three groups:
     * - burnTicks: Elements present in activeTicks but not in targetTicks.
     * - mintTicks: Elements present in targetTicks but not in activeTicks.
     * - stayTicks: Elements common to both activeTicks and targetTicks.
     *
     *@return burnTicks Ticks that will be burnt
     *@return mintTicks Ticks that will be minted
     *@return stayTicks Ticks that will either be minted more or burned partially.
     */

    function analyzeTickChanges(
        int24[] memory _activeTicks,
        int24[] memory _targetTicks
    ) public pure returns (int24[] memory burnTicks, int24[] memory mintTicks, int24[] memory stayTicks) {
        bool[] memory isActiveInTarget = new bool[](_activeTicks.length);
        bool[] memory isTargetInActive = new bool[](_targetTicks.length);

        Categories memory counts;
        Categories memory indices;

        // Check for common elements and elements unique to _activeTicks
        for (uint256 i; i < _activeTicks.length; i++) {
            bool found = false;
            for (uint256 j; j < _targetTicks.length; j++) {
                if (_activeTicks[i] == _targetTicks[j]) {
                    found = true;
                    isTargetInActive[j] = true;
                    counts.stay++;
                    break;
                }
            }
            if (!found) {
                counts.burn++;
            } else {
                isActiveInTarget[i] = true;
            }
        }

        // Count elements unique to _targetTicks and check their validity
        for (uint256 i; i < _targetTicks.length; i++) {
            if (!isTargetInActive[i]) {
                counts.mint++;
            }
        }

        // Initialize arrays with correct sizes
        burnTicks = new int24[](counts.burn);
        mintTicks = new int24[](counts.mint);
        stayTicks = new int24[](counts.stay);

        // Populate the arrays
        for (uint256 i; i < _activeTicks.length; i++) {
            if (!isActiveInTarget[i]) {
                burnTicks[indices.burn++] = _activeTicks[i];
            } else {
                stayTicks[indices.stay++] = _activeTicks[i];
            }
        }

        for (uint256 i; i < _targetTicks.length; i++) {
            if (!isTargetInActive[i]) {
                mintTicks[indices.mint++] = _targetTicks[i];
            }
        }

        return (burnTicks, mintTicks, stayTicks);
    }

    function validateMintTicks(int24[] memory mintTicks) public view returns (int24[] memory validatedMintTicks) {
        uint256 validCount;

        // Count valid mint ticks
        for (uint256 i; i < mintTicks.length; i++) {
            if (automator.checkMintValidity(mintTicks[i])) {
                validCount++;
            }
        }

        // Initialize array with correct size
        validatedMintTicks = new int24[](validCount);

        // Populate the array with valid mint ticks
        uint256 index;
        for (uint256 i; i < mintTicks.length; i++) {
            if (automator.checkMintValidity(mintTicks[i])) {
                validatedMintTicks[index++] = mintTicks[i];
            }
        }

        return validatedMintTicks;
    }

    function removeCurrentTick(int24[] memory _ticks) public view returns (int24[] memory updatedTicks) {
        int24 currentLT = this.getCurrentLT(pool.currentTick());
        uint256 validCount;

        // Count ticks that are not equal to currentTick
        for (uint256 i; i < _ticks.length; i++) {
            if (_ticks[i] != currentLT) {
                validCount++;
            }
        }

        // Initialize array with the correct size
        updatedTicks = new int24[](validCount);

        // Populate the array with ticks not equal to currentLT
        uint256 index;
        for (uint256 i; i < _ticks.length; i++) {
            if (_ticks[i] != currentLT) {
                updatedTicks[index++] = _ticks[i];
            }
        }

        return updatedTicks;
    }

    /**
     * @notice Retrieves liquidity amount of ticks
     * @param _activeTicks An array of active tick indexes for which information is to be retrieved.
     * @return _activeTicksInfo An array of RebalanceTickInfo structures, each containing the tick
     *         and its corresponding liquidity.
     */
    function getActiveTicksInfo(
        int24[] memory _activeTicks
    ) public view returns (IAutomator.RebalanceTickInfo[] memory _activeTicksInfo) {
        _activeTicksInfo = new IAutomator.RebalanceTickInfo[](_activeTicks.length);

        for (uint256 i; i < _activeTicks.length; i++) {
            uint128 _tickLiquidity = automator.getTickAllLiquidity(_activeTicks[i]);
            _activeTicksInfo[i] = IAutomator.RebalanceTickInfo(_activeTicks[i], _tickLiquidity);
        }
    }

    /**
     * @notice Determines information about burnable and unburnable liquidity for given ticks in a Uniswap V3 pool.
     *         It calculates the total burnable and unburnable value in assets for each tick.
     * @dev This function iterates over the given ticks, calculating the free (burnable) and locked (unburnable)
     *      liquidity for each. It uses this information to compute the total value in assets that can be withdrawn
     *      and the total value that cannot be withdrawn.
     * @param _burnTicks An array of tick indexes to be analyzed for burnable liquidity.
     * @return _burnTicksInfo An array of `RebalanceTickInfo` objects, each representing the burnable tick and its liquidity amount.
     * @return _totalBurnableValueInAssets The total value of assets that can be burned across all analyzed ticks.
     * @return _totalUnburnableValueInAssets The total value of assets that cannot be burned across all analyzed ticks.
     */
    function getBurnableTicksInfo(
        int24[] memory _burnTicks
    )
        public
        view
        returns (
            IAutomator.RebalanceTickInfo[] memory _burnTicksInfo,
            uint256 _totalBurnableValueInAssets,
            uint256 _totalUnburnableValueInAssets
        )
    {
        IAutomator.RebalanceTickInfo[] memory tempBurnTicksInfo = new IAutomator.RebalanceTickInfo[](_burnTicks.length);
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        AssetInfo memory _freeTotal;
        AssetInfo memory _lockedTotal;

        uint256 _burnTicksLength = 0;

        for (uint256 i; i < _burnTicks.length; i++) {
            int24 _tick = _burnTicks[i];

            uint128 _burnableLiquidity = automator.getTickFreeLiquidity(_tick);

            uint256 _tempAssets;
            uint256 _tempCounterAssets;

            (_tempAssets, _tempCounterAssets) = getAssetsForLiquidity(
                _sqrtRatioX96,
                _tick.getSqrtRatioAtTick(),
                (_tick + poolTickSpacing).getSqrtRatioAtTick(),
                _burnableLiquidity
            );
            _freeTotal.assets += _tempAssets;
            _freeTotal.counterAssets += _tempCounterAssets;

            (_tempAssets, _tempCounterAssets) = getAssetsForLiquidity(
                _sqrtRatioX96,
                _tick.getSqrtRatioAtTick(),
                (_tick + poolTickSpacing).getSqrtRatioAtTick(),
                automator.getTickAllLiquidity(_tick) - _burnableLiquidity //unBurnableLiquidity
            );
            _lockedTotal.assets += _tempAssets;
            _lockedTotal.counterAssets += _tempCounterAssets;

            //avoid executing rebalance with 0 liquidity.
            if (_burnableLiquidity > 0) {
                tempBurnTicksInfo[_burnTicksLength] = IAutomator.RebalanceTickInfo(_burnTicks[i], _burnableLiquidity);
                _burnTicksLength++;
            }
        }

        _burnTicksInfo = new IAutomator.RebalanceTickInfo[](_burnTicksLength);
        for (uint256 j; j < _burnTicksLength; j++) {
            _burnTicksInfo[j] = tempBurnTicksInfo[j];
        }

        _totalBurnableValueInAssets =
            _freeTotal.assets +
            OracleLibrary.getQuoteAtTick(
                pool.currentTick(),
                uint128(_freeTotal.counterAssets),
                address(counterAsset),
                address(asset)
            );

        _totalUnburnableValueInAssets =
            _lockedTotal.assets +
            OracleLibrary.getQuoteAtTick(
                pool.currentTick(),
                uint128(_lockedTotal.counterAssets),
                address(counterAsset),
                address(asset)
            );
    }

    /**
     * @notice Classifies 'stay' ticks as either 'mint' or 'burn' based on the target liquidity.
     *         This function takes arrays of mint, burn, and stay tick information along with
     *         the target liquidity amount. It adjusts the mint and burn arrays to include
     *         ticks from the stay array based on whether they need more or less liquidity
     *         compared to the target.
     * @dev The function first calculates the number of ticks that need to be moved from
     *      the 'stay' category to either 'mint' or 'burn' categories. It then creates new
     *      arrays for mint and burn ticks, including these additional ticks. The function
     *      finally returns these new arrays.
     *      Note: This function assumes that liquidity cannot be zero.
     * @param _mintTicksInfo Array of current mint tick information.
     * @param _burnTicksInfo Array of current burn tick information.
     * @param _stayTicksInfo Array of current stay tick information.
     * @param _targetLiquidity The target liquidity for each tick.
     * @return newMintTicksInfo An array of updated mint tick information including modified stay ticks.
     * @return newBurnTicksInfo An array of updated burn tick information including modified stay ticks.
     */
    function classifyStayTicks(
        IAutomator.RebalanceTickInfo[] memory _mintTicksInfo,
        IAutomator.RebalanceTickInfo[] memory _burnTicksInfo,
        IAutomator.RebalanceTickInfo[] memory _stayTicksInfo,
        uint128 _targetLiquidity
    ) public pure returns (IAutomator.RebalanceTickInfo[] memory, IAutomator.RebalanceTickInfo[] memory) {
        //1. extend mint and burn array
        uint256 mintExtensionCounter = 0;
        uint256 burnExtensionCounter = 0;

        for (uint256 i; i < _stayTicksInfo.length; i++) {
            //prevent mint/burn 0 liquidity
            if (_targetLiquidity < _stayTicksInfo[i].liquidity) {
                burnExtensionCounter++;
            } else if (_targetLiquidity > _stayTicksInfo[i].liquidity) {
                mintExtensionCounter++;
            }
        }

        IAutomator.RebalanceTickInfo[] memory newMintTicksInfo = new IAutomator.RebalanceTickInfo[](
            _mintTicksInfo.length + mintExtensionCounter
        );
        IAutomator.RebalanceTickInfo[] memory newBurnTicksInfo = new IAutomator.RebalanceTickInfo[](
            _burnTicksInfo.length + burnExtensionCounter
        );

        //copy the original to new
        for (uint256 i; i < _mintTicksInfo.length; i++) {
            newMintTicksInfo[i] = _mintTicksInfo[i];
        }
        for (uint256 i; i < _burnTicksInfo.length; i++) {
            newBurnTicksInfo[i] = _burnTicksInfo[i];
        }

        //classify the stay into mint or burn
        uint256 newMintIndex = _mintTicksInfo.length;
        uint256 newBurnIndex = _burnTicksInfo.length;
        for (uint256 i; i < _stayTicksInfo.length; i++) {
            //prevent mint/burn 0 liquidity
            if (_targetLiquidity < _stayTicksInfo[i].liquidity) {
                newBurnTicksInfo[newBurnIndex++] = IAutomator.RebalanceTickInfo(
                    _stayTicksInfo[i].tick,
                    _stayTicksInfo[i].liquidity - _targetLiquidity
                );
            } else if (_targetLiquidity > _stayTicksInfo[i].liquidity) {
                newMintTicksInfo[newMintIndex++] = IAutomator.RebalanceTickInfo(
                    _stayTicksInfo[i].tick,
                    _targetLiquidity - _stayTicksInfo[i].liquidity
                );
            }
        }

        return (newMintTicksInfo, newBurnTicksInfo);
    }

    /**
     * @notice Calculates the total assets required per liquidity unit for a given set of ticks in a Uniswap V3 pool.
     * @dev This function iterates over a given array of tick indexes and calculates the total assets and counter-assets
     *      required to provide one unit of liquidity (constant LIQUIDITY_UNIT) for each tick. The final return value is the sum of all assets
     *      required for these ticks.
     *      - `_assetsTotal` accumulates the total amount of the primary asset required.
     *      - `_counterAssetsTotal` accumulates the total amount of the counter asset required.
     *      Each amount is slightly adjusted (by adding 1) to account for potential rounding down in the
     *      `getAssetsForLiquidity` function.
     * @param _ticks An array of tick indexes for which the assets per liquidity unit are to be calculated.
     * @return _assetsPerLiquidityUnit Total amount of assets needed to create LIQUIDITY_UNIT across _ticks.
     */
    function getAssetsPerLiquidityUnit(int24[] memory _ticks) public view returns (uint256) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        uint256 _assetsTotal;
        uint256 _counterAssetsTotal;

        for (uint256 i; i < _ticks.length; i++) {
            int24 _lt = _ticks[i]; //lowerTick
            int24 _ut = _lt + poolTickSpacing; //upperTick

            (uint256 _assets, uint256 _counterAssets) = getAssetsForLiquidity(
                _sqrtRatioX96,
                _lt.getSqrtRatioAtTick(),
                _ut.getSqrtRatioAtTick(),
                LIQUIDITY_UNIT
            );

            //_assets/_counterAssets is rounded down amount, so plus 1 for safety
            _assetsTotal += (_assets + 1);
            _counterAssetsTotal += (_counterAssets + 1);
        }

        uint256 _assetsPerLiquidityUnit = _assetsTotal +
            OracleLibrary.getQuoteAtTick(
                pool.currentTick(),
                uint128(_counterAssetsTotal),
                address(counterAsset),
                address(asset)
            );

        return _assetsPerLiquidityUnit;
    }

    function getAssetsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal view returns (uint256, uint256) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );

        return reversed ? (amount1, amount0) : (amount0, amount1);
    }
}

