// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import {IAlgebraMintCallback} from "./IAlgebraMintCallback.sol";
import {IAlgebraSwapCallback} from "./IAlgebraSwapCallback.sol";
import {ConeCamelotVaultStorage} from "./ConeCamelotVaultStorage.sol";
import {TickMath} from "./uniswap_TickMath.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import {FullMath, LiquidityAmounts} from "./uniswap_LiquidityAmounts.sol";
import {ConeCamelotLibrary} from "./ConeCamelotLibrary.sol";

contract ConeCamelotVault is
    IAlgebraMintCallback,
    IAlgebraSwapCallback,
    ConeCamelotVaultStorage
{
    using SafeERC20 for IERC20;
    using TickMath for int24;

    event Minted(
        address receiver,
        uint256 mintAmount,
        uint256 amount0In,
        uint256 amount1In,
        uint128 liquidityMinted
    );

    event Burned(
        address receiver,
        uint256 burnAmount,
        uint256 amount0Out,
        uint256 amount1Out,
        uint128 liquidityBurned
    );

    event CollectedMerkl(IERC20, uint256);
    error InvalidTickSpacing(int24 lowerTick, int24 upperTick);
    error MaxAmountExceeded(
        uint256 maxAmount0,
        uint256 maxAmount1,
        uint256 amount0,
        uint256 amount1
    );
    error MinAmountNotReached(
        uint256 minAmount0,
        uint256 minAmount1,
        uint256 amount0,
        uint256 amount1
    );
    error tooLittleMint(
        uint128 liquidityMinted,
        uint256 amount0,
        uint256 amount1
    );

    // solhint-disable-next-line max-line-length
    constructor(address _coneTreasury) ConeCamelotVaultStorage(_coneTreasury) {} // solhint-disable-line no-empty-blocks

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function algebraMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        require(msg.sender == address(pool));

        if (amount0Owed > 0) token0.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(msg.sender, amount1Owed);
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external override {
        require(msg.sender == address(pool));

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    // User functions => Should be called via a Router

    /// @notice mint ConeVault Shares, fractional shares of a Uniswap V3 position/strategy
    /// @dev to compute the amouint of tokens necessary to mint `mintAmount` see getMintAmounts
    /// @param mintAmount The number of shares to mint
    /// @param receiver The account to receive the minted shares
    /// @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
    /// @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
    /// @return liquidityMinted amount of liquidity added to the underlying Uniswap V3 position
    // solhint-disable-next-line function-max-lines, code-complexity
    function mint(
        uint256 mintAmount,
        address receiver,
        uint256 maxAmount0,
        uint256 maxAmount1
    )
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted)
    {
        require(mintAmount > 0);
        require(
            restrictedMintToggle != 11111 || msg.sender == _manager,
            "resricted"
        );
        uint256 amount0Max;
        uint256 amount1Max;
        uint128 liquidityMintedMax;
        for (uint256 index = 0; index < 3; ++index) {
            (amount0Max, amount1Max, liquidityMintedMax) = _mintInternal(
                RangeType(index),
                ((mintAmount * percentageBIPS[RangeType(index)]) / 10000)
            );
            amount0 += amount0Max;
            amount1 += amount1Max;
            liquidityMinted += liquidityMintedMax;
        }
        if (amount0 > maxAmount0 || amount1 > maxAmount1)
            revert MaxAmountExceeded(maxAmount0, maxAmount1, amount0, amount1);
        if (
            liquidityMinted < minLiquidityToMint || amount0 == 0 || amount1 == 0
        ) revert tooLittleMint(liquidityMinted, amount0, amount1);
        _mint(receiver, mintAmount);
        emit Minted(receiver, mintAmount, amount0, amount1, liquidityMinted);
    }

    function _mintInternal(
        RangeType _range,
        uint256 _mintAmount
    )
        internal
        returns (uint256 amount0, uint256 amount1, uint128 liquidityMinted)
    {
        uint256 rangeSupply = tokensForRange[_range];

        (uint160 sqrtRatioX96, , , , , , , ) = pool.globalState();
        if (rangeSupply > 0) {
            (
                uint256 amount0Current,
                uint256 amount1Current
            ) = ConeCamelotLibrary.getUnderlyingBalances(
                    address(this),
                    uint8(_range)
                );
            amount0 = FullMath.mulDivRoundingUp(
                amount0Current,
                _mintAmount,
                rangeSupply
            );
            amount1 = FullMath.mulDivRoundingUp(
                amount1Current,
                _mintAmount,
                rangeSupply
            );
        } else {
            // if supply is 0 mintAmount == liquidity to deposit
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTicks[_range].getSqrtRatioAtTick(),
                upperTicks[_range].getSqrtRatioAtTick(),
                SafeCast.toUint128(_mintAmount)
            );
        }
        // transfer amounts owed to contract
        if (amount0 > 0) {
            token0.safeTransferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            token1.safeTransferFrom(msg.sender, address(this), amount1);
        }

        // deposit as much new liquidity as possible, adding any leftover token0 or token1 to the balances.
        liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTicks[_range].getSqrtRatioAtTick(),
            upperTicks[_range].getSqrtRatioAtTick(),
            token0.balanceOf(address(this))-managerBalance0-coneBalance0,
            token1.balanceOf(address(this))-managerBalance1-coneBalance1
        );
        liquidityInRange[_range] += liquidityMinted;
        pool.mint(
            address(this),
            address(this),
            lowerTicks[_range],
            upperTicks[_range],
            liquidityMinted,
            ""
        );
        tokensForRange[_range] += _mintAmount;
    }

    /// @notice burn ConeVault Shares (shares of a Uniswap V3 position) and receive underlying
    /// @param burnAmount The number of shares to burn
    /// @param receiver The account to receive the underlying amounts of token0 and token1
    /// @return amount0 amount of token0 transferred to receiver for burning `burnAmount`
    /// @return amount1 amount of token1 transferred to receiver for burning `burnAmount`
    /// @return liquidityBurned amount of liquidity removed from the underlying Uniswap V3 position
    // solhint-disable-next-line function-max-lines
    function burn(
        uint256 burnAmount,
        address receiver,
        uint256 minAmount0,
        uint256 minAmount1
    )
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint128 liquidityBurned)
    {
        require(burnAmount > 0);
        uint256 currTotalSupply = totalSupply();

        // getting liquidity from different ranges
        _burn(msg.sender, burnAmount);
        uint256 burnLeft;
        uint256 burnRight;
        (burnLeft, burnRight, liquidityBurned) = processBurns(burnAmount);

        // Add the users fees as well
        amount0 =
            burnLeft +
            FullMath.mulDiv(
                token0.balanceOf(address(this)) -
                    burnLeft -
                    managerBalance0 -
                    coneBalance0,
                burnAmount,
                currTotalSupply
            );
        amount1 =
            burnRight +
            FullMath.mulDiv(
                token1.balanceOf(address(this)) -
                    burnRight -
                    managerBalance1 -
                    coneBalance1,
                burnAmount,
                currTotalSupply
            );

        ensureMinAmounts(amount0, amount1, minAmount0, minAmount1);
        safeTransferHelper(token0, receiver, amount0);
        safeTransferHelper(token1, receiver, amount1);

        emit Burned(receiver, burnAmount, amount0, amount1, liquidityBurned);
    }

    function processBurns(
        uint256 burnAmount
    )
        internal
        returns (uint256 burnLeft, uint256 burnRight, uint128 liquidityBurnt)
    {
        for (uint256 index = 0; index < 3; ++index) {
            (
                uint256 burntToken0ForRange,
                uint256 burnToken1ForRange,
                uint128 liquidityBurned_
            ) = processBurnForRange(
                    RangeType(index),
                    ((burnAmount * percentageBIPS[RangeType(index)]) / 10000)
                );
            burnLeft += burntToken0ForRange;
            burnRight += burnToken1ForRange;
            liquidityBurnt += liquidityBurned_;
        }
    }

    function ensureMinAmounts(
        uint256 amount0,
        uint256 amount1,
        uint256 minAmount0,
        uint256 minAmount1
    ) internal pure {
        if (amount0 < minAmount0 || amount1 < minAmount1)
            revert MinAmountNotReached(
                minAmount0,
                minAmount1,
                amount0,
                amount1
            );
    }

    function safeTransferHelper(
        IERC20 token,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            token.safeTransfer(to, amount);
        }
    }

    function processBurnForRange(
        RangeType range,
        uint256 burnAmount
    ) internal returns (uint256, uint256, uint128) {
        (uint128 liquidity, , , , , ) = pool.positions(
            ConeCamelotLibrary.getPositionID(address(this), uint8(range))
        );
        uint256 rangeSupply = tokensForRange[range];
        int24 lowTick = lowerTicks[range];
        int24 upTick = upperTicks[range];
        uint256 liquidityBurned_ = FullMath.mulDiv(
            burnAmount,
            liquidity,
            rangeSupply
        );
        tokensForRange[range] -= burnAmount;
        liquidityInRange[range] -= liquidityBurned_;
        uint128 liquidityBurned = SafeCast.toUint128(liquidityBurned_);

        (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) = _withdraw(
            lowTick,
            upTick,
            liquidityBurned
        );
        (fee0, fee1) = _applyFees(fee0, fee1);
        emit FeesEarned(fee0, fee1);
        return (burn0, burn1, liquidityBurned);
    }

    // Manager Functions => Called by Pool Manager

    /// @notice Change the range of underlying UniswapV3 position, only manager can call
    /// @dev When changing the range the inventory of token0 and token1 may be rebalanced
    /// with a swap to deposit as much liquidity as possible into the new position. Swap parameters
    /// can be computed by simulating the whole operation: remove all liquidity, deposit as much
    /// as possible into new position, then observe how much of token0 or token1 is leftover.
    /// Swap a proportion of this leftover to deposit more liquidity into the position, since
    /// any leftover will be unused and sit idle until the next rebalance.
    /// @param newLowerTick The new lower bound of the position's range
    /// @param newUpperTick The new upper bound of the position's range
    /// @param swapThresholdPrice slippage parameter on the swap as a max or min sqrtPriceX96
    /// @param swapAmountBPS amount of token to swap as proportion of total. Pass 0 to ignore swap.
    /// @param zeroForOne Which token to input into the swap (true = token0, false = token1)
    /// @param rangeType The range to rebalance
    /// @param minLiquidityExpected The minimum amount of liquidity expected to be added to the position
    // solhint-disable-next-line function-max-lines
    function executiveRebalance(
        int24 newLowerTick,
        int24 newUpperTick,
        uint160 swapThresholdPrice,
        uint256 swapAmountBPS,
        bool zeroForOne,
        RangeType rangeType,
        uint128 minLiquidityExpected
    ) external onlyManager {
        uint128 liquidity;
        uint128 newLiquidity;
        if (
            !ConeCamelotLibrary.validateTickSpacing(
                address(pool),
                newLowerTick,
                newUpperTick
            )
        ) revert InvalidTickSpacing(newLowerTick, newUpperTick);
        if (totalSupply() > 0) {
            (liquidity, , , , , ) = pool.positions(
                ConeCamelotLibrary.getPositionID(
                    address(this),
                    uint8(rangeType)
                )
            );
            liquidityInRange[rangeType] = 0;
            if (liquidity > 0) {
                (, , uint256 fee0, uint256 fee1) = _withdraw(
                    lowerTicks[rangeType],
                    upperTicks[rangeType],
                    liquidity
                );

                (fee0, fee1) = _applyFees(fee0, fee1);
                emit FeesEarned(fee0, fee1);
            }

            lowerTicks[rangeType] = newLowerTick;
            upperTicks[rangeType] = newUpperTick;

            uint256 reinvest0 = token0.balanceOf(address(this)) -
                managerBalance0 -
                coneBalance0;
            uint256 reinvest1 = token1.balanceOf(address(this)) -
                managerBalance1 -
                coneBalance1;

            _deposit(
                newLowerTick,
                newUpperTick,
                reinvest0,
                reinvest1,
                swapThresholdPrice,
                swapAmountBPS,
                zeroForOne
            );

            (newLiquidity, , , , , ) = pool.positions(
                ConeCamelotLibrary.getPositionID(
                    address(this),
                    uint8(rangeType)
                )
            );
            liquidityInRange[rangeType] = newLiquidity;
            require(newLiquidity > minLiquidityExpected);
        } else {
            lowerTicks[rangeType] = newLowerTick;
            upperTicks[rangeType] = newUpperTick;
        }

        emit Rebalance(newLowerTick, newUpperTick, liquidity, newLiquidity);
    }

    /// @notice withdraw manager fees accrued or do an emergency withdraw only used during beta phase for making funds safuuu
    /// this burning doesnot burn the vault tokens so users positions are still maintained for redistribution.
    function withdrawManagerBalance(
        bool isEmergencyWithdraw
    ) external onlyManager {
        uint256 amount0 = managerBalance0;
        uint256 amount1 = managerBalance1;

        managerBalance0 = 0;
        managerBalance1 = 0;
        if (isEmergencyWithdraw && restrictedMintToggle == 11111) {
            for (uint256 index = 0; index < 3; ++index) {
                (uint256 burn0, uint256 burn1, ) = processBurnForRange(
                    RangeType(index),
                    tokensForRange[RangeType(index)]
                );
                amount0 += burn0;
                amount1 += burn1;
            }
            emit EmergencyWithdraw();
        }
        token0.safeTransfer(managerTreasury, amount0);
        token1.safeTransfer(managerTreasury, amount1);
    }

    /// @notice withdraw merkl accrued
    function withdrawMerkl(address _token) external onlyManager {
        IERC20 token = IERC20(_token);
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(coneTreasury, amount);
        emit CollectedMerkl(token, amount);
    }
}

