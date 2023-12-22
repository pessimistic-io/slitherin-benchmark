// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";

/**
 * @notice Contract with logic to integrate with uniswap V3 liquidity pools
 * @dev Non view functions in this contract should be called via delegateCall
 */
contract UniswapV3Integration {
    using SafeERC20 for IERC20;

    /// @notice Private variable storing the address of the logic contract
    address private immutable self = address(this);

    /**
     * @notice Require that the current call is a delegatecall
     */
    function checkDelegateCall() private view {
        require(address(this) != self, "delegatecall only");
    }

    modifier onlyDelegateCall() {
        checkDelegateCall();
        _;
    }

    /**
     * @notice Mints a new uniswap NFT by depositing into the pool
     */
    function mint(address uniswapPositionManager, address want, int24 tick0, int24 tick1) external onlyDelegateCall returns (uint tokenId) {
        IUniswapV3Pool pool = IUniswapV3Pool(want);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fees = pool.fee();
        INonfungiblePositionManager.MintParams memory mintParams;
        mintParams = INonfungiblePositionManager.MintParams(
            token0, token1,
            fees,
            tick0, tick1,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        uint amount0; uint amount1;
        (tokenId,,amount0, amount1) = INonfungiblePositionManager(uniswapPositionManager).mint(mintParams);
    }

    /**
     * @notice Deposit funds into uniswap pool
     * @dev minAmounts for params are set to tolerate no slippage since prior borrowing should result in
     * tokens being in the perfect ratio to deposit into pool
     */
    function increaseLiquidity(address uniswapPositionManager, uint tokenId, address want) external onlyDelegateCall {
        IUniswapV3Pool pool = IUniswapV3Pool(want);
        address token0 = pool.token0();
        address token1 = pool.token1();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (,,,,,int24 tick0, int24 tick1,,,,,) = INonfungiblePositionManager(uniswapPositionManager).positions(tokenId);
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tick0);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tick1);
        uint amount0 = IERC20(token0).balanceOf(address(this));
        uint amount1 = IERC20(token1).balanceOf(address(this));
        uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
        if (expectedLiquidity>0) {
            INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams(
                tokenId,
                amount0,
                amount1,
                0,
                0,
                block.timestamp
            );
            INonfungiblePositionManager(uniswapPositionManager).increaseLiquidity(params);
        }
    }

    /**
     * @notice Withdraw liquidity from liquidity pool
     */
    function decreaseLiquidity(address uniswapPositionManager, uint tokenId, uint128 liquidityToRemove) external onlyDelegateCall {
        INonfungiblePositionManager.DecreaseLiquidityParams memory withdrawParams = INonfungiblePositionManager
            .DecreaseLiquidityParams(tokenId, liquidityToRemove, 0, 0, block.timestamp);
        (uint amount0, uint amount1) = INonfungiblePositionManager(uniswapPositionManager)
            .decreaseLiquidity(withdrawParams);
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams(
            tokenId, address(this), uint128(amount0), uint128(amount1)
        );
        INonfungiblePositionManager(uniswapPositionManager).collect(collectParams);
    }

    /**
     * @notice Harvest accumulated rewards from the uniswap pool
     */
    function harvest(address uniswapPositionManager, uint tokenId) external onlyDelegateCall returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            tokenId,
            address(this),
            2 ** 128 - 1,
            2 ** 128 - 1
        );
        (amount0, amount1) = INonfungiblePositionManager(uniswapPositionManager).collect(params);
    }

    /**
     * @notice Calculate the ratio between token0 and token1 for the uniswap v3 pool
     * based on the ticks and current pool state
     */
    function getRatio(address want, int24 tick0, int24 tick1) external view returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(want);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tick0);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tick1);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            pool.liquidity()
        );
    }

    /**
     * @notice Gets the price of a token from the UniswapV3 Pool in terms of the other token
     * @dev The price returned is in the same format as calling oracle.getPriceInTermsOf
     * The returned value represents how many tokens of the pool's other token are equal to a single
     * token (10**ERC20(token).decimals()) of the input token
     */
    function pairPrice(address want, address token) public view returns (uint) {
        IUniswapV3Pool pool = IUniswapV3Pool(want);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        if (token == pool.token0()) {
            return FullMath.mulDiv(10 ** ERC20(token).decimals(), uint(sqrtPriceX96) ** 2, 2**192);
        } else {
            return FullMath.mulDiv(10 ** ERC20(token).decimals(), 2 ** 192, uint(sqrtPriceX96) ** 2);
        }
    }

    function getPendingFees(
        address uniswapPositionManager,
        uint256 tokenId
    ) external view returns (uint256 feeAmt0, uint256 feeAmt1) {
        if (tokenId==0) return (0, 0);
        int24 tickLower;
        int24 tickUpper;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        IUniswapV3Pool pool;
        {
            address token0;
            address token1;
            uint24 fee;
            (
                ,
                ,
                token0,
                token1,
                fee,
                tickLower,
                tickUpper,
                ,
                feeGrowthInside0LastX128,
                feeGrowthInside1LastX128,
                ,
            ) = INonfungiblePositionManager(uniswapPositionManager).positions(tokenId);
            pool = IUniswapV3Pool(
                IUniswapV3Factory(INonfungiblePositionManager(uniswapPositionManager).factory()).getPool(token0, token1, fee)
            );
        }
        (, int24 curTick, , , , , ) = pool.slot0();

        (uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(
            _getPositionID(uniswapPositionManager, tickLower, tickUpper)
        );

        // console.log(feeGrowthInside0LastX128, pool.feeGrowthGlobal0X128(), feeGrowthInside1LastX128, pool.feeGrowthGlobal1X128());
        // (, , uint feeGrowthOutsideLower, , , , , ) = pool.ticks(tickLower);
        // (, , uint feeGrowthOutsideUpper, , , , , ) = pool.ticks(tickUpper);
        // console.log(feeGrowthOutsideLower, feeGrowthOutsideUpper);


        feeAmt0 =
            _computeFeesEarned(pool, true, feeGrowthInside0LastX128, curTick, tickLower, tickUpper, liquidity) +
            tokensOwed0;
        feeAmt1 =
            _computeFeesEarned(pool, false, feeGrowthInside1LastX128, curTick, tickLower, tickUpper, liquidity) +
            tokensOwed1;
    }

    function _getPositionID(
        address _owner,
        int24 _lowerTick,
        int24 _upperTick
    ) internal pure returns (bytes32 positionId) {
        return keccak256(abi.encodePacked(_owner, _lowerTick, _upperTick));
    }

    /**
     * @notice Computes the fees earned by providing liquidity
     * @dev ref: from arrakis finance: https://github.com/ArrakisFinance/vault-v1-core/blob/main/contracts/ArrakisVaultV1.sol
     * @param _pool The UniswapV3 Pool to use
     * @param _isZero Is Zero Fee
     * @param _feeGrowthInsideLast feeGrowthInside0LastX128 or feeGrowthInside1LastX128 depending on the token to compute
     * @param _tick The current tick
     * @param _lowerTick The lower tick (range) where the position sits
     * @param _upperTick The upper tick (range) where the position sits
     * @param _liquidity The amount of liquidity supplied
     * @return fee The Fee generated either token0 or token1 depending on the _feeGrowthInsideLast
     */
    function _computeFeesEarned(
        IUniswapV3Pool _pool,
        bool _isZero,
        uint _feeGrowthInsideLast,
        int24 _tick,
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) internal view returns (uint fee) {
        uint feeGrowthOutsideLower;
        uint feeGrowthOutsideUpper;
        uint feeGrowthGlobal;
        if (_isZero) {
            feeGrowthGlobal = _pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = _pool.ticks(_lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = _pool.ticks(_upperTick);
        } else {
            feeGrowthGlobal = _pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = _pool.ticks(_lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = _pool.ticks(_upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint feeGrowthBelow;
            if (_tick >= _lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint feeGrowthAbove;
            if (_tick < _upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint feeGrowthInside = feeGrowthGlobal -
                feeGrowthBelow -
                feeGrowthAbove;
            fee =
                (_liquidity * (feeGrowthInside - _feeGrowthInsideLast)) /
                2 ** 128;
        }
    }
}
