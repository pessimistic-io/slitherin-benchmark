//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {IConeCamelotVaultStorage} from "./IConeCamelotVaultStorage.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath, LiquidityAmounts} from "./LiquidityAmounts.sol";
import {IUniswapV3TickSpacing} from "./IUniswapV3TickSpacing.sol";
import {IERC20} from "./IERC20.sol";
import {SafeCast} from "./SafeCast.sol";

library ConeCamelotLibraryV2 {
    using TickMath for int24;
    using SafeCast for uint256;

    // Assuming the declaration of the VaultData struct somewhere in the code as:
    struct VaultData {
        address token0;
        address token1;
        uint256 managerBalance0;
        uint256 managerBalance1;
        uint256 coneBalance0;
        uint256 coneBalance1;
        IAlgebraPool pool;
        int24 lowerTick;
        int24 upperTick;
        address vault;
    }

    struct PoolData {
        uint128 liquidity;
        uint256 feeGrowthInside0Last;
        uint256 feeGrowthInside1Last;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function applyFees(address _vault, uint256 _fee0, uint256 _fee1)
        external
        view
        returns (uint256 coneBalance0, uint256 coneBalance1, uint256 managerBalance0, uint256 managerBalance1, uint256 rawFee0, uint256 rawFee1)
    {
        uint256 coneFeeBPS = IConeCamelotVaultStorage(_vault).coneFeeBPS();
        uint256 managerFeeBPS = IConeCamelotVaultStorage(_vault).managerFeeBPS();

        coneBalance0 = IConeCamelotVaultStorage(_vault).coneBalance0() + (_fee0 * coneFeeBPS) / 10000;
        coneBalance1 = IConeCamelotVaultStorage(_vault).coneBalance1() + (_fee1 * coneFeeBPS) / 10000;
        managerBalance0 = IConeCamelotVaultStorage(_vault).managerBalance0() + (_fee0 * managerFeeBPS) / 10000;
        managerBalance1 = IConeCamelotVaultStorage(_vault).managerBalance1() + (_fee1 * managerFeeBPS) / 10000;
        uint256 deduct0 = (_fee0 * (coneFeeBPS + managerFeeBPS)) / 10000;
        uint256 deduct1 = (_fee1 * (coneFeeBPS + managerFeeBPS)) / 10000;
        rawFee0 = _fee0 - deduct0;
        rawFee1 = _fee1 - deduct1;
    }

    function subtractAdminFees(address _vault, uint256 rawFee0, uint256 rawFee1)
        public
        view
        returns (uint256 fee0, uint256 fee1)
    {
        uint256 coneFeeBPS = IConeCamelotVaultStorage(_vault).coneFeeBPS();
        uint256 managerFeeBPS = IConeCamelotVaultStorage(_vault).managerFeeBPS();
        uint256 deduct0 = (rawFee0 * (coneFeeBPS + managerFeeBPS)) / 10000;
        uint256 deduct1 = (rawFee1 * (coneFeeBPS + managerFeeBPS)) / 10000;
        fee0 = rawFee0 - deduct0;
        fee1 = rawFee1 - deduct1;
    }

    function computeFeesEarned(
        address _pool,
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity,
        int24 lowerTick,
        int24 upperTick
    ) public view returns (uint256 fee) {
        IAlgebraPool pool = IAlgebraPool(_pool);

        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;

        if (isZero) {
            feeGrowthGlobal = pool.totalFeeGrowth0Token();
            (,, feeGrowthOutsideLower,,,,,) = pool.ticks(lowerTick);
            (,, feeGrowthOutsideUpper,,,,,) = pool.ticks(upperTick);
        } else {
            feeGrowthGlobal = pool.totalFeeGrowth1Token();
            (,,, feeGrowthOutsideLower,,,,) = pool.ticks(lowerTick);
            (,,, feeGrowthOutsideUpper,,,,) = pool.ticks(upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee = FullMath.mulDiv(liquidity, feeGrowthInside - feeGrowthInsideLast, 0x100000000000000000000000000000000);
        }
    }

    /// @notice compute maximum shares that can be minted from `amount0Max` and `amount1Max`
    /// @param amount0Max The maximum amount of token0 to forward on mint
    /// @param amount0Max The maximum amount of token1 to forward on mint
    /// @return amount0 actual amount of token0 to forward when minting `mintAmount`
    /// @return amount1 actual amount of token1 to forward when minting `mintAmount`
    /// @return mintAmount maximum number of shares mintable
    function getMintAmounts(address _vault, uint256 amount0Max, uint256 amount1Max, uint8 rangeType)
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 mintAmount)
    {
        uint256 totalSupply = IConeCamelotVaultStorage(_vault).tokensForRange(rangeType);
        if (totalSupply > 0) {
            (amount0, amount1, mintAmount) = computeMintAmounts(_vault, totalSupply, amount0Max, amount1Max, rangeType);
        } else {
            uint160 sqrtRatioX96lower = IConeCamelotVaultStorage(_vault).lowerTicks(rangeType).getSqrtRatioAtTick();
            uint160 sqrtRatioX96upper = IConeCamelotVaultStorage(_vault).upperTicks(rangeType).getSqrtRatioAtTick();
            (uint160 sqrtRatioX96,,,,,,,) = IAlgebraPool(IConeCamelotVaultStorage(_vault).pool()).globalState();
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                sqrtRatioX96lower,
                sqrtRatioX96upper,
                amount0Max,
                amount1Max
            );
            mintAmount = uint256(newLiquidity);
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                sqrtRatioX96lower,
                sqrtRatioX96upper,
                newLiquidity
            );
        }
    }

    function getPositionID(address _vault, uint8 _range) public view returns (bytes32 positionID) {
        int24 _lowerTick = IConeCamelotVaultStorage(_vault).lowerTicks(_range);
        int24 _upperTick = IConeCamelotVaultStorage(_vault).upperTicks(_range);

        bytes32 positionKey;
        address This = address(_vault);
        assembly {
            positionKey := or(shl(24, or(shl(24, This), and(_lowerTick, 0xFFFFFF))), and(_upperTick, 0xFFFFFF))
        }
        return positionKey;
    }

    function computeMintAmounts(
        address _vault,
        uint256 totalSupply,
        uint256 amount0Max,
        uint256 amount1Max,
        uint8 rangeType
    ) public view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(_vault, rangeType);

        // compute proportional amount of tokens to mint
        if (amount0Current == 0 && amount1Current > 0) {
            mintAmount = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
        } else if (amount1Current == 0 && amount0Current > 0) {
            mintAmount = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
        } else if (amount0Current == 0 && amount1Current == 0) {
            revert("");
        } else {
            // only if both are non-zero
            uint256 amount0Mint = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
            uint256 amount1Mint = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
            require(amount0Mint > 0 && amount1Mint > 0, "mint 0");

            mintAmount = amount0Mint < amount1Mint ? amount0Mint : amount1Mint;
        }

        // compute amounts owed to contract
        amount0 = FullMath.mulDivRoundingUp(mintAmount, amount0Current, totalSupply);
        amount1 = FullMath.mulDivRoundingUp(mintAmount, amount1Current, totalSupply);
    }

    /// @notice compute total underlying holdings of the G-UNI token supply
    /// includes current liquidity invested in algebra position, current fees earned
    /// and any uninvested leftover (but does not include manager or external fees accrued)
    /// @return amount0Current current total underlying balance of token0
    /// @return amount1Current current total underlying balance of token1
    function getUnderlyingBalances(address _vault, uint8 _rangeType) public view returns (uint256, uint256) {
        (uint160 sqrtRatioX96, int24 tick,,,,,,) = IAlgebraPool(IConeCamelotVaultStorage(_vault).pool()).globalState();
        return getUnderlyingBalancesAtTick(_vault, sqrtRatioX96, tick, _rangeType);
    }

    function getUnderlyingBalancesAtPrice(address _vault, uint160 sqrtRatioX96, uint8 range)
        public
        view
        returns (uint256, uint256)
    {
        (, int24 tick,,,,,,) = IAlgebraPool(IConeCamelotVaultStorage(_vault).pool()).globalState();
        return getUnderlyingBalancesAtTick(_vault, sqrtRatioX96, tick, range);
    }

    function getUnderlyingBalancesAtTick(address _vault, uint160 sqrtRatioX96, int24 tick, uint8 range)
        public
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        VaultData memory data = getVaultData(_vault, range);

        (uint128 liquidity,,,,,) = data.pool.positions(getPositionID(_vault, range));

        // compute current fees earned
        (uint256 fee0, uint256 fee1) = computeFees(data, tick, range);

        (fee0, fee1) = subtractAdminFees(_vault, fee0, fee1);

        (amount0Current, amount1Current) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, data.lowerTick.getSqrtRatioAtTick(), data.upperTick.getSqrtRatioAtTick(), liquidity
        );

        // add any leftover in contract to current holdings
        amount0Current += fee0;
        amount1Current += fee1;
    }

    function getVaultData(address _vault, uint8 range) public view returns (VaultData memory) {
        IConeCamelotVaultStorage vaultStorage = IConeCamelotVaultStorage(_vault);

        return VaultData({
            lowerTick: vaultStorage.lowerTicks(range),
            upperTick: vaultStorage.upperTicks(range),
            token0: address(vaultStorage.token0()),
            token1: address(vaultStorage.token1()),
            managerBalance0: vaultStorage.managerBalance0(),
            managerBalance1: vaultStorage.managerBalance1(),
            coneBalance0: vaultStorage.coneBalance0(),
            coneBalance1: vaultStorage.coneBalance1(),
            pool: IAlgebraPool(vaultStorage.pool()),
            vault: _vault
        });
    }

    function getPoolData(address _vault, uint8 _range) public view returns (PoolData memory) {
        IConeCamelotVaultStorage vaultStorage = IConeCamelotVaultStorage(_vault);

        (
            uint256 liquidity,
            ,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = IAlgebraPool(vaultStorage.pool()).positions(getPositionID(_vault, _range));
        return PoolData({
            liquidity: liquidity.toUint128(),
            feeGrowthInside0Last: feeGrowthInside0Last,
            feeGrowthInside1Last: feeGrowthInside1Last,
            tokensOwed0: tokensOwed0,
            tokensOwed1: tokensOwed1
        });
    }

    function computeFees(VaultData memory data, int24 tick, uint8 range)
        public
        view
        returns (uint256 fee0, uint256 fee1)
    {
        PoolData memory poolData = getPoolData(data.vault, range);

        fee0 = computeFeesEarned(
            address(data.pool),
            true,
            poolData.feeGrowthInside0Last,
            tick,
            poolData.liquidity,
            data.lowerTick,
            data.upperTick
        ) + uint256(poolData.tokensOwed0);

        fee1 = computeFeesEarned(
            address(data.pool),
            false,
            poolData.feeGrowthInside1Last,
            tick,
            poolData.liquidity,
            data.lowerTick,
            data.upperTick
        ) + uint256(poolData.tokensOwed1);
    }

    function validateTickSpacing(address uniPool, int24 lowerTick, int24 upperTick) external view returns (bool) {
        int24 spacing = IUniswapV3TickSpacing(uniPool).tickSpacing();
        return lowerTick < upperTick && lowerTick % spacing == 0 && upperTick % spacing == 0;
    }

}
