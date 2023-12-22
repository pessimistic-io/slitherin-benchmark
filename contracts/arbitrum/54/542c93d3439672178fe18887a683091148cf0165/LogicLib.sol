//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {SafeCastUpgradeable} from "./SafeCastUpgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "./IERC20MetadataUpgradeable.sol";
import {Address} from "./Address.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IPancakeV3Pool} from "./IPancakeV3Pool.sol";
import {TickMath} from "./TickMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {FullMath} from "./FullMath.sol";
import {IRangeProtocolVault} from "./IRangeProtocolVault.sol";
import {VaultErrors} from "./VaultErrors.sol";
import {IWETH9} from "./IWETH9.sol";
import {DataTypes} from "./DataTypes.sol";

library LogicLib {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using TickMath for int24;

    /// Performance fee cannot be set more than 20% of the fee earned from pancake v3 pool.
    uint16 public constant MAX_PERFORMANCE_FEE_BPS = 2000;
    /// Managing fee cannot be set more than 1% of the total fee earned.
    uint16 public constant MAX_MANAGING_FEE_BPS = 100;

    event Minted(
        address indexed receiver,
        uint256 mintAmount,
        uint256 amount0In,
        uint256 amount1In
    );
    event Burned(
        address indexed receiver,
        uint256 burnAmount,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event LiquidityAdded(
        uint256 liquidityMinted,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0In,
        uint256 amount1In
    );
    event LiquidityRemoved(
        uint256 liquidityRemoved,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Out,
        uint256 amount1Out
    );
    event FeesEarned(uint256 feesEarned0, uint256 feesEarned1);
    event FeesUpdated(uint16 managingFee, uint16 performanceFee, uint16 otherFee);
    event InThePositionStatusSet(bool inThePosition);
    event Swapped(bool zeroForOne, int256 amount0, int256 amount1);
    event TicksSet(int24 lowerTick, int24 upperTick);
    event MintStarted();
    event OtherFeeRecipientSet(address otherFeeRecipient);

    /**
     * @notice updateTicks it is called by the contract manager to update the ticks.
     * It can only be called once total supply is zero and the vault has not active position
     * in the pancake pool
     * @param _lowerTick lowerTick to set
     * @param _upperTick upperTick to set
     */
    function updateTicks(
        DataTypes.State storage state,
        int24 _lowerTick,
        int24 _upperTick
    ) external {
        if (IERC20Upgradeable(address(this)).totalSupply() != 0 || state.inThePosition)
            revert VaultErrors.NotAllowedToUpdateTicks();
        _updateTicks(state, _lowerTick, _upperTick);

        if (!state.mintStarted) {
            state.mintStarted = true;
            emit MintStarted();
        }
    }

    /// @notice pancakeV3MintCallback Pancake V3 callback fn, called back on pool.mint
    function pancakeV3MintCallback(
        DataTypes.State storage state,
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata
    ) external {
        if (msg.sender != address(state.pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Owed > 0) state.token0.safeTransfer(msg.sender, amount0Owed);

        if (amount1Owed > 0) state.token1.safeTransfer(msg.sender, amount1Owed);
    }

    /// @notice pancakeV3SwapCallback Pancake v3 callback fn, called back on pool.swap
    function pancakeV3SwapCallback(
        DataTypes.State storage state,
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (msg.sender != address(state.pool)) revert VaultErrors.OnlyPoolAllowed();

        if (amount0Delta > 0) state.token0.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) state.token1.safeTransfer(msg.sender, uint256(amount1Delta));
    }

    struct MintLocalVars {
        bool inThePosition;
        uint256 totalSupply;
        int24 lowerTick;
        int24 upperTick;
        IPancakeV3Pool pool;
    }

    /**
     * @notice mint mints range vault shares, fractional shares of a Pancake V3 position/strategy
     * to compute the amount of tokens necessary to mint `mintAmount` see getMintAmounts
     * @param mintAmount The number of shares to mint
     * @param maxAmounts max amounts to add in token0 and token1.
     * @return amount0 amount of token0 transferred from msg.sender to mint `mintAmount`
     * @return amount1 amount of token1 transferred from msg.sender to mint `mintAmount`
     */
    function mint(
        DataTypes.State storage state,
        uint256 mintAmount,
        bool depositNative,
        uint256[2] calldata maxAmounts
    ) external returns (uint256 amount0, uint256 amount1) {
        if (!state.mintStarted) revert VaultErrors.MintNotStarted();
        if (mintAmount == 0) revert VaultErrors.InvalidMintAmount();
        IRangeProtocolVault vault = IRangeProtocolVault(address(this));
        MintLocalVars memory vars;
        (vars.inThePosition, vars.totalSupply, vars.lowerTick, vars.upperTick, vars.pool) = (
            state.inThePosition,
            vault.totalSupply(),
            state.lowerTick,
            state.upperTick,
            state.pool
        );
        (uint160 sqrtRatioX96, , , , , , ) = vars.pool.slot0();

        if (vars.totalSupply > 0) {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(state);
            amount0 = FullMath.mulDivRoundingUp(amount0Current, mintAmount, vars.totalSupply);
            amount1 = FullMath.mulDivRoundingUp(amount1Current, mintAmount, vars.totalSupply);
        } else if (vars.inThePosition) {
            // If total supply is zero then inThePosition must be set to accept token0 and token1 based on currently set ticks.
            // This branch will be executed for the first mint and as well as each time total supply is to be changed from zero to non-zero.
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                vars.lowerTick.getSqrtRatioAtTick(),
                vars.upperTick.getSqrtRatioAtTick(),
                SafeCastUpgradeable.toUint128(mintAmount)
            );
        } else {
            // If total supply is zero and the vault is not in the position then mint cannot be accepted based on the assumptions
            // that being out of the pool renders currently set ticks unusable and totalSupply being zero does not allow
            // calculating correct amounts of amount0 and amount1 to be accepted from the user.
            // This branch will be executed if all users remove their liquidity from the vault i.e. total supply is zero from non-zero and
            // the vault is out of the position i.e. no valid tick range to calculate the vault's mint shares.
            // Manager must call initialize function with valid tick ranges to enable the minting again.
            revert VaultErrors.MintNotAllowed();
        }

        if (amount0 > maxAmounts[0] || amount1 > maxAmounts[1])
            revert VaultErrors.SlippageExceedThreshold();

        vault.mint(msg.sender, mintAmount);
        _processDeposit(state, depositNative, amount0, amount1);

        if (vars.inThePosition) {
            uint128 liquidityMinted = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                vars.lowerTick.getSqrtRatioAtTick(),
                vars.upperTick.getSqrtRatioAtTick(),
                amount0,
                amount1
            );
            vars.pool.mint(address(this), vars.lowerTick, vars.upperTick, liquidityMinted, "");
        }
        emit Minted(msg.sender, mintAmount, amount0, amount1);

        if (address(this).balance != 0) msg.sender.call{value: address(this).balance}("");
    }

    function _processDeposit(
        DataTypes.State storage state,
        bool depositNative,
        uint256 amount0,
        uint256 amount1
    ) private {
        DataTypes.UserVault storage userVault = state.userVaults[msg.sender];
        IWETH9 WETH9 = IWETH9(state.WETH9);
        IERC20Upgradeable token0 = state.token0;
        IERC20Upgradeable token1 = state.token1;

        userVault.token0 += amount0;
        userVault.token1 += amount1;

        if (!userVault.exists) {
            userVault.exists = true;
            state.users.push(msg.sender);
        }

        (bool isToken0Native, bool isToken1Native) = (
            address(token0) == address(WETH9),
            address(token1) == address(WETH9)
        );
        if (amount0 != 0) {
            if (isToken0Native && depositNative) {
                if (msg.value < amount0) {
                    revert VaultErrors.InsufficientNativeTokenAmount(msg.value);
                }
                WETH9.deposit{value: amount0}();
            } else {
                token0.safeTransferFrom(msg.sender, address(this), amount0);
            }
        }

        if (amount1 != 0) {
            if (isToken1Native && depositNative) {
                if (msg.value < amount1) {
                    revert VaultErrors.InsufficientNativeTokenAmount(msg.value);
                }
                WETH9.deposit{value: amount1}();
            } else {
                token1.safeTransferFrom(msg.sender, address(this), amount1);
            }
        }
    }

    struct BurnLocalVars {
        uint256 totalSupply;
        IERC20Upgradeable token0;
        IERC20Upgradeable token1;
        uint256 managerBalance0;
        uint256 managerBalance1;
        uint256 passiveBalance0;
        uint256 passiveBalance1;
        uint256 balanceBefore;
    }

    /**
     * @notice burn burns range vault shares (shares of a Pancake V3 position) and receive underlying
     * @param burnAmount The number of shares to burn
     * @return amount0 amount of token0 transferred to msg.sender for burning {burnAmount}
     * @return amount1 amount of token1 transferred to msg.sender for burning {burnAmount}
     */
    function burn(
        DataTypes.State storage state,
        uint256 burnAmount,
        bool withdrawNative,
        uint256[2] calldata minAmounts
    ) external returns (uint256 amount0, uint256 amount1) {
        if (burnAmount == 0) revert VaultErrors.InvalidBurnAmount();
        IRangeProtocolVault vault = IRangeProtocolVault(address(this));
        BurnLocalVars memory vars;
        (
            vars.totalSupply,
            vars.token0,
            vars.token1,
            vars.managerBalance0,
            vars.managerBalance1,
            vars.balanceBefore
        ) = (
            vault.totalSupply(),
            state.token0,
            state.token1,
            state.managerBalance0,
            state.managerBalance1,
            vault.balanceOf(msg.sender)
        );
        if (state.inThePosition) {
            (uint128 liquidity, , , , ) = state.pool.positions(getPositionID(state));
            uint256 liquidityBurned_ = FullMath.mulDiv(burnAmount, liquidity, vars.totalSupply);
            uint128 liquidityBurned = SafeCastUpgradeable.toUint128(liquidityBurned_);
            (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) = _withdraw(
                state,
                liquidityBurned
            );

            _applyPerformanceAndOtherFee(state, fee0, fee1);
            (fee0, fee1) = _netPerformanceAndOtherFees(state, fee0, fee1);
            emit FeesEarned(fee0, fee1);

            vars.passiveBalance0 = vars.token0.balanceOf(address(this)) - burn0;
            vars.passiveBalance1 = vars.token1.balanceOf(address(this)) - burn1;
            if (vars.passiveBalance0 > vars.managerBalance0)
                vars.passiveBalance0 -= vars.managerBalance0;
            if (vars.passiveBalance1 > vars.managerBalance1)
                vars.passiveBalance1 -= vars.managerBalance1;

            amount0 = burn0 + FullMath.mulDiv(vars.passiveBalance0, burnAmount, vars.totalSupply);
            amount1 = burn1 + FullMath.mulDiv(vars.passiveBalance1, burnAmount, vars.totalSupply);
        } else {
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(state);
            amount0 = FullMath.mulDiv(amount0Current, burnAmount, vars.totalSupply);
            amount1 = FullMath.mulDiv(amount1Current, burnAmount, vars.totalSupply);
        }

        if (amount0 < minAmounts[0] || amount1 < minAmounts[1])
            revert VaultErrors.SlippageExceedThreshold();

        vault.burn(msg.sender, burnAmount);
        _applyManagingFee(state, amount0, amount1);
        (amount0, amount1) = _netManagingFees(state, amount0, amount1);
        _processWithdraw(
            state,
            vars.balanceBefore,
            vars.balanceBefore - burnAmount,
            withdrawNative,
            amount0,
            amount1
        );

        emit Burned(msg.sender, burnAmount, amount0, amount1);
    }

    function _processWithdraw(
        DataTypes.State storage state,
        uint256 balanceBefore,
        uint256 balanceAfter,
        bool withdrawNative,
        uint256 amount0,
        uint256 amount1
    ) private {
        DataTypes.UserVault storage userVault = state.userVaults[msg.sender];
        IWETH9 WETH9 = IWETH9(state.WETH9);
        IERC20Upgradeable token0 = state.token0;
        IERC20Upgradeable token1 = state.token1;

        userVault.token0 = (userVault.token0 * balanceAfter) / balanceBefore;
        userVault.token1 = (userVault.token1 * balanceAfter) / balanceBefore;

        (bool isToken0Native, bool isToken1Native) = (
            address(token0) == address(WETH9),
            address(token1) == address(WETH9)
        );

        uint256 weth9Amount = 0;
        if (amount0 != 0) {
            if (isToken0Native && withdrawNative) {
                weth9Amount = amount0;
            } else {
                token0.safeTransfer(msg.sender, amount0);
            }
        }
        if (amount1 != 0) {
            if (isToken1Native && withdrawNative) {
                weth9Amount = amount1;
            } else {
                token1.safeTransfer(msg.sender, amount1);
            }
        }

        if (weth9Amount != 0) {
            WETH9.withdraw(amount0);
            msg.sender.call{value: weth9Amount}("");
        }
    }

    /**
     * @notice removeLiquidity removes liquidity from pancake pool and receives underlying tokens
     * in the vault contract.
     */
    function removeLiquidity(
        DataTypes.State storage state,
        uint256[2] calldata minAmounts
    ) external {
        (uint128 liquidity, , , , ) = state.pool.positions(getPositionID(state));

        if (liquidity > 0) {
            int24 _lowerTick = state.lowerTick;
            int24 _upperTick = state.upperTick;
            (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) = _withdraw(
                state,
                liquidity
            );

            if (amount0 < minAmounts[0] || amount1 < minAmounts[1])
                revert VaultErrors.SlippageExceedThreshold();

            emit LiquidityRemoved(liquidity, _lowerTick, _upperTick, amount0, amount1);

            _applyPerformanceAndOtherFee(state, fee0, fee1);
            (fee0, fee1) = _netPerformanceAndOtherFees(state, fee0, fee1);
            emit FeesEarned(fee0, fee1);
        }

        // TicksSet event is not emitted here since the emitting would create a new position on subgraph but
        // the following statement is to only disallow any liquidity provision through the vault unless done
        // by manager (taking into account any features added in future).
        state.lowerTick = state.upperTick;
        state.inThePosition = false;
        emit InThePositionStatusSet(false);
    }

    /**
     * @dev Mars@RangeProtocol
     * @notice swap swaps token0 for token1 (token0 in, token1 out), or token1 for token0 (token1 in token0 out).
     * Zero for one will cause the price: amount1 / amount0 lower, otherwise it will cause the price higher
     * @param zeroForOne The direction of the swap, true is swap token0 for token1, false is swap token1 to token0
     * @param swapAmount The exact input token amount of the swap
     * @param sqrtPriceLimitX96 threshold price ratio after the swap.
     * If zero for one, the price cannot be lower (swap make price lower) than this threshold value after the swap
     * If one for zero, the price cannot be greater (swap make price higher) than this threshold value after the swap
     * @param minAmountIn minimum amount to protect against slippage.
     * @return amount0 If positive represents exact input token0 amount after this swap, msg.sender paid amount,
     * or exact output token0 amount (negative), msg.sender received amount
     * @return amount1 If positive represents exact input token1 amount after this swap, msg.sender paid amount,
     * or exact output token1 amount (negative), msg.sender received amount
     */
    function swap(
        DataTypes.State storage state,
        bool zeroForOne,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountIn
    ) external returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = state.pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            sqrtPriceLimitX96,
            ""
        );
        if (
            (zeroForOne && uint256(-amount1) < minAmountIn) ||
            (!zeroForOne && uint256(-amount0) < minAmountIn)
        ) revert VaultErrors.SlippageExceedThreshold();

        emit Swapped(zeroForOne, amount0, amount1);
    }

    /**
     * @dev Mars@RangeProtocol
     * @notice addLiquidity allows manager to add liquidity into pancake pool into newer tick ranges.
     * @param newLowerTick new lower tick to deposit liquidity into
     * @param newUpperTick new upper tick to deposit liquidity into
     * @param amount0 max amount of amount0 to use
     * @param amount1 max amount of amount1 to use
     * @param maxAmounts max amounts to add for slippage protection
     */
    function addLiquidity(
        DataTypes.State storage state,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 amount0,
        uint256 amount1,
        uint256[2] calldata maxAmounts
    ) external returns (uint256 remainingAmount0, uint256 remainingAmount1) {
        if (state.inThePosition) revert VaultErrors.LiquidityAlreadyAdded();

        (uint160 sqrtRatioX96, , , , , , ) = state.pool.slot0();
        uint128 baseLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            newLowerTick.getSqrtRatioAtTick(),
            newUpperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );

        if (baseLiquidity > 0) {
            (uint256 amountDeposited0, uint256 amountDeposited1) = state.pool.mint(
                address(this),
                newLowerTick,
                newUpperTick,
                baseLiquidity,
                ""
            );
            if (amountDeposited0 > maxAmounts[0] || amountDeposited1 > maxAmounts[1])
                revert VaultErrors.SlippageExceedThreshold();

            _updateTicks(state, newLowerTick, newUpperTick);
            emit LiquidityAdded(
                baseLiquidity,
                newLowerTick,
                newUpperTick,
                amountDeposited0,
                amountDeposited1
            );

            // Should return remaining token number for swap
            remainingAmount0 = amount0 - amountDeposited0;
            remainingAmount1 = amount1 - amountDeposited1;
        }
    }

    /*
     * @dev Allows rebalance of the vault by manager using off-chain quote and non-pool venues.
     * @param target address of the target swap venue.
     * @param swapData data to send to the target swap venue.
     * @param zeroForOne swap direction, true for x -> y; false for y -> x.
     * @param amount amount of tokenIn to swap.
     **/
    function rebalance(
        DataTypes.State storage state,
        address target,
        bytes calldata swapData,
        bool zeroForOne,
        uint256 amount
    ) external {
        if (state.lastRebalanceTimestamp + 2 hours > block.timestamp)
            revert VaultErrors.RebalanceIntervalNotReached();
        state.lastRebalanceTimestamp = block.timestamp;
        if (amount == 0) revert VaultErrors.ZeroRebalanceAmount();
        IERC20MetadataUpgradeable token0 = IERC20MetadataUpgradeable(address(state.token0));
        IERC20MetadataUpgradeable token1 = IERC20MetadataUpgradeable(address(state.token1));
        AggregatorV3Interface priceOracle0 = AggregatorV3Interface(state.priceOracle0);
        AggregatorV3Interface priceOracle1 = AggregatorV3Interface(state.priceOracle1);

        (zeroForOne ? token0 : token1).approve(target, amount);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        Address.functionCall(target, swapData);
        uint256 balance0After = token0.balanceOf(address(this));
        uint256 balance1After = token1.balanceOf(address(this));

        uint256 amount0Delta = balance0After > balance0Before
            ? balance0After - balance0Before
            : balance0Before - balance0After;
        uint256 amount1Delta = balance1After > balance1Before
            ? balance1After - balance1Before
            : balance1Before - balance1After;

        uint256 swapPrice = (amount1Delta * 10 ** token0.decimals()) / amount0Delta;
        (, int256 token0Price, , , ) = priceOracle0.latestRoundData();
        (, int256 token1Price, , , ) = priceOracle1.latestRoundData();

        uint256 priceFromOracle = (uint256(token0Price) *
            10 ** priceOracle1.decimals() *
            10 ** token1.decimals()) /
            uint256(token1Price) /
            10 ** priceOracle0.decimals();

        uint256 swapRatio = (priceFromOracle * 10_000) / swapPrice;
        if (swapRatio < 9900 || swapRatio > 10100) {
            revert VaultErrors.RebalanceSlippageExceedsThreshold();
        }
    }

    /**
     * @dev pullFeeFromPool pulls accrued fee from pancake v3 pool that position has accrued since
     * last collection.
     */
    function pullFeeFromPool(DataTypes.State storage state) external {
        _pullFeeFromPool(state);
    }

    /// @notice collectManager collects manager fees accrued
    function collectManager(DataTypes.State storage state, address manager) external {
        uint256 amount0 = state.managerBalance0;
        uint256 amount1 = state.managerBalance1;
        state.managerBalance0 = 0;
        state.managerBalance1 = 0;

        if (amount0 > 0) {
            state.token0.safeTransfer(manager, amount0);
        }
        if (amount1 > 0) {
            state.token1.safeTransfer(manager, amount1);
        }
    }

    function collectOtherFee(DataTypes.State storage state) external {
        uint256 amount0 = state.otherBalance0;
        uint256 amount1 = state.otherBalance1;
        state.otherBalance0 = 0;
        state.otherBalance1 = 0;

        address _otherFeeRecipient = state.otherFeeRecipient;
        if (amount0 > 0) state.token0.safeTransfer(_otherFeeRecipient, amount0);
        if (amount1 > 0) state.token1.safeTransfer(_otherFeeRecipient, amount1);
    }

    function setOtherFeeRecipient(
        DataTypes.State storage state,
        address newOtherFeeRecipient
    ) external {
        if (newOtherFeeRecipient == address(0x0)) revert VaultErrors.ZeroOtherFeeRecipientAddress();
        state.otherFeeRecipient = newOtherFeeRecipient;
        emit OtherFeeRecipientSet(newOtherFeeRecipient);
    }

    /**
     * @notice updateFees allows updating of managing and performance fees
     */
    function updateFees(
        DataTypes.State storage state,
        uint16 newManagingFee,
        uint16 newPerformanceFee,
        uint16 newOtherFee
    ) external {
        _updateFees(state, newManagingFee, newPerformanceFee, newOtherFee);
    }

    /**
     * @notice compute maximum shares that can be minted from `amount0Max` and `amount1Max`
     * @param amount0Max The maximum amount of token0 to forward on mint
     * @param amount1Max The maximum amount of token1 to forward on mint
     * @return amount0 actual amount of token0 to forward when minting `mintAmount`
     * @return amount1 actual amount of token1 to forward when minting `mintAmount`
     * @return mintAmount maximum number of shares mintable
     */
    function getMintAmounts(
        DataTypes.State storage state,
        uint256 amount0Max,
        uint256 amount1Max
    ) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        if (!state.mintStarted) revert VaultErrors.MintNotStarted();
        uint256 totalSupply = IRangeProtocolVault(address(this)).totalSupply();
        if (totalSupply > 0) {
            (amount0, amount1, mintAmount) = _calcMintAmounts(
                state,
                totalSupply,
                amount0Max,
                amount1Max
            );
        } else if (state.inThePosition) {
            (uint160 sqrtRatioX96, , , , , , ) = state.pool.slot0();
            (int24 lowerTick, int24 upperTick) = (state.lowerTick, state.upperTick);
            uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                amount0Max,
                amount1Max
            );
            mintAmount = uint256(newLiquidity);
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                newLiquidity
            );
        }
    }

    /**
     * @notice getCurrentFees returns the current uncollected fees
     * @return fee0 uncollected fee in token0
     * @return fee1 uncollected fee in token1
     */
    function getCurrentFees(
        DataTypes.State storage state
    ) external view returns (uint256 fee0, uint256 fee1) {
        (, int24 tick, , , , , ) = state.pool.slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = state.pool.positions(getPositionID(state));
        fee0 =
            _feesEarned(state, true, feeGrowthInside0Last, tick, liquidity) +
            uint256(tokensOwed0);
        fee1 =
            _feesEarned(state, false, feeGrowthInside1Last, tick, liquidity) +
            uint256(tokensOwed1);
        (fee0, fee1) = _netPerformanceAndOtherFees(state, fee0, fee1);
    }

    /**
     * @notice returns array of current user vaults. This function is only intended to be called off-chain.
     * @param fromIdx start index to fetch the user vaults info from.
     * @param toIdx end index to fetch the user vault to.
     */
    function getUserVaults(
        DataTypes.State storage state,
        uint256 fromIdx,
        uint256 toIdx
    ) external view returns (DataTypes.UserVaultInfo[] memory) {
        if (fromIdx == 0 && toIdx == 0) {
            toIdx = state.users.length;
        }
        DataTypes.UserVaultInfo[] memory usersVaultInfo = new DataTypes.UserVaultInfo[](
            toIdx - fromIdx
        );
        uint256 count;
        for (uint256 i = fromIdx; i < toIdx; i++) {
            DataTypes.UserVault memory userVault = state.userVaults[state.users[i]];
            usersVaultInfo[count++] = DataTypes.UserVaultInfo({
                user: state.users[i],
                token0: userVault.token0,
                token1: userVault.token1
            });
        }
        return usersVaultInfo;
    }

    /**
     * @notice getPositionID returns the position id of the vault in pancake pool
     * @return positionID position id of the vault in pancake pool
     */
    function getPositionID(DataTypes.State storage state) public view returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), state.lowerTick, state.upperTick));
    }

    /**
     * @notice compute total underlying token0 and token1 token supply at current price
     * includes current liquidity invested in pancake position, current fees earned
     * and any uninvested leftover (but does not include manager fees accrued)
     * @return amount0Current current total underlying balance of token0
     * @return amount1Current current total underlying balance of token1
     */
    function getUnderlyingBalances(
        DataTypes.State storage state
    ) public view returns (uint256 amount0Current, uint256 amount1Current) {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = state.pool.slot0();
        return _getUnderlyingBalances(state, sqrtRatioX96, tick);
    }

    function getUnderlyingBalancesByShare(
        DataTypes.State storage state,
        uint256 shares
    ) external view returns (uint256 amount0, uint256 amount1) {
        uint256 _totalSupply = IRangeProtocolVault(address(this)).totalSupply();
        if (_totalSupply != 0) {
            // getUnderlyingBalances already applies performanceFee
            (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(state);
            amount0 = (shares * amount0Current) / _totalSupply;
            amount1 = (shares * amount1Current) / _totalSupply;
            // apply managing fee
            (amount0, amount1) = _netManagingFees(state, amount0, amount1);
        }
    }

    /**
     * @notice _getUnderlyingBalances internal function to calculate underlying balances
     * @param sqrtRatioX96 price to calculate underlying balances at
     * @param tick tick at the given price
     * @return amount0Current current amount of token0
     * @return amount1Current current amount of token1
     */
    function _getUnderlyingBalances(
        DataTypes.State storage state,
        uint160 sqrtRatioX96,
        int24 tick
    ) internal view returns (uint256 amount0Current, uint256 amount1Current) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = state.pool.positions(getPositionID(state));

        uint256 fee0;
        uint256 fee1;
        if (liquidity != 0) {
            (amount0Current, amount1Current) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                state.lowerTick.getSqrtRatioAtTick(),
                state.upperTick.getSqrtRatioAtTick(),
                liquidity
            );
            fee0 =
                _feesEarned(state, true, feeGrowthInside0Last, tick, liquidity) +
                uint256(tokensOwed0);
            fee1 =
                _feesEarned(state, false, feeGrowthInside1Last, tick, liquidity) +
                uint256(tokensOwed1);
            (fee0, fee1) = _netPerformanceAndOtherFees(state, fee0, fee1);
        }

        uint256 passiveBalance0 = fee0 + state.token0.balanceOf(address(this));
        uint256 passiveBalance1 = fee1 + state.token1.balanceOf(address(this));
        amount0Current += passiveBalance0 > state.managerBalance0
            ? passiveBalance0 - state.managerBalance0
            : passiveBalance0;
        amount1Current += passiveBalance1 > state.managerBalance1
            ? passiveBalance1 - state.managerBalance1
            : passiveBalance1;
    }

    /**
     * @notice The userVault mapping is updated before the vault share tokens are transferred between the users.
     * The data from this mapping is used by off-chain strategy manager. The data in this mapping does not impact
     * the on-chain behaviour of vault or users' funds.
     * @dev transfers userVault amounts based on the transferring user vault shares
     * @param from address to transfer userVault amount from
     * @param to address to transfer userVault amount to
     */
    function _beforeTokenTransfer(
        DataTypes.State storage state,
        address from,
        address to,
        uint256 amount
    ) external {
        // for mint and burn the user vaults adjustment are handled in the respective functions
        if (from == address(0x0) || to == address(0x0)) return;
        if (!state.userVaults[to].exists) {
            state.userVaults[to].exists = true;
            state.users.push(to);
        }
        uint256 senderBalanceBefore = IERC20Upgradeable(address(this)).balanceOf(from);
        uint256 senderBalanceAfter = senderBalanceBefore - amount;
        uint256 token0Amount = state.userVaults[from].token0 -
            (state.userVaults[from].token0 * senderBalanceAfter) /
            senderBalanceBefore;

        uint256 token1Amount = state.userVaults[from].token1 -
            (state.userVaults[from].token1 * senderBalanceAfter) /
            senderBalanceBefore;

        state.userVaults[from].token0 -= token0Amount;
        state.userVaults[from].token1 -= token1Amount;

        state.userVaults[to].token0 += token0Amount;
        state.userVaults[to].token1 += token1Amount;
    }

    /**
     * @notice _withdraw internal function to withdraw liquidity from uniswap pool
     * @param liquidity liquidity to remove from the uniswap pool
     */
    function _withdraw(
        DataTypes.State storage state,
        uint128 liquidity
    ) private returns (uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1) {
        int24 _lowerTick = state.lowerTick;
        int24 _upperTick = state.upperTick;
        uint256 preBalance0 = state.token0.balanceOf(address(this));
        uint256 preBalance1 = state.token1.balanceOf(address(this));
        (burn0, burn1) = state.pool.burn(_lowerTick, _upperTick, liquidity);
        state.pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );
        fee0 = state.token0.balanceOf(address(this)) - preBalance0 - burn0;
        fee1 = state.token1.balanceOf(address(this)) - preBalance1 - burn1;
    }

    /**
     * @notice _calcMintAmounts internal function to calculate the amount based on the max supply of token0 and token1
     * and current supply of RangeVault shares.
     * @param totalSupply current total supply of range vault shares
     * @param amount0Max max amount of token0 to compute mint amount
     * @param amount1Max max amount of token1 to compute mint amount
     */
    function _calcMintAmounts(
        DataTypes.State storage state,
        uint256 totalSupply,
        uint256 amount0Max,
        uint256 amount1Max
    ) private view returns (uint256 amount0, uint256 amount1, uint256 mintAmount) {
        (uint256 amount0Current, uint256 amount1Current) = getUnderlyingBalances(state);
        if (amount0Current == 0 && amount1Current > 0) {
            mintAmount = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
        } else if (amount1Current == 0 && amount0Current > 0) {
            mintAmount = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
        } else if (amount0Current == 0 && amount1Current == 0) {
            revert VaultErrors.ZeroUnderlyingBalance();
        } else {
            uint256 amount0Mint = FullMath.mulDiv(amount0Max, totalSupply, amount0Current);
            uint256 amount1Mint = FullMath.mulDiv(amount1Max, totalSupply, amount1Current);
            if (amount0Mint == 0 || amount1Mint == 0) revert VaultErrors.ZeroMintAmount();
            mintAmount = amount0Mint < amount1Mint ? amount0Mint : amount1Mint;
        }

        amount0 = FullMath.mulDivRoundingUp(mintAmount, amount0Current, totalSupply);
        amount1 = FullMath.mulDivRoundingUp(mintAmount, amount1Current, totalSupply);
    }

    /**
     * @notice _feesEarned internal function to return the fees accrued
     * @param isZero true to compute fee for token0 and false to compute fee for token1
     * @param feeGrowthInsideLast last time the fee was realized for the vault in pancake pool
     */
    function _feesEarned(
        DataTypes.State storage state,
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        (IPancakeV3Pool pool, int24 lowerTick, int24 upperTick) = (
            state.pool,
            state.lowerTick,
            state.upperTick
        );
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(upperTick);
        }

        unchecked {
            uint256 feeGrowthBelow;
            if (tick >= lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            uint256 feeGrowthAbove;
            if (tick < upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }
            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;

            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    /**
     * @notice _applyManagingFee applies the managing fee to the notional value of the redeeming user.
     * @param amount0 user's notional value in token0
     * @param amount1 user's notional value in token1
     */
    function _applyManagingFee(
        DataTypes.State storage state,
        uint256 amount0,
        uint256 amount1
    ) private {
        uint256 _managingFee = state.managingFee;
        state.managerBalance0 += (amount0 * _managingFee) / 10_000;
        state.managerBalance1 += (amount1 * _managingFee) / 10_000;
    }

    /**
     * @notice _applyPerformanceAndOtherFee applies the performance fee to the fees earned from pancake v3 pool.
     * @param fee0 fee earned in token0
     * @param fee1 fee earned in token1
     */
    function _applyPerformanceAndOtherFee(
        DataTypes.State storage state,
        uint256 fee0,
        uint256 fee1
    ) private {
        uint256 _performanceFee = state.performanceFee;
        state.managerBalance0 += (fee0 * _performanceFee) / 10_000;
        state.managerBalance1 += (fee1 * _performanceFee) / 10_000;

        uint256 _otherFee = state.otherFee;
        state.otherBalance0 += (fee0 * _otherFee) / 10_000;
        state.otherBalance1 += (fee1 * _otherFee) / 10_000;
    }

    /**
     * @notice _netManagingFees computes the fee share for manager from notional value of the redeeming user.
     * @param amount0 user's notional value in token0
     * @param amount1 user's notional value in token1
     * @return amount0AfterFee user's notional value in token0 after managing fee deduction
     * @return amount1AfterFee user's notional value in token1 after managing fee deduction
     */
    function _netManagingFees(
        DataTypes.State storage state,
        uint256 amount0,
        uint256 amount1
    ) private view returns (uint256 amount0AfterFee, uint256 amount1AfterFee) {
        uint256 _managingFee = state.managingFee;
        uint256 deduct0 = (amount0 * _managingFee) / 10_000;
        uint256 deduct1 = (amount1 * _managingFee) / 10_000;
        amount0AfterFee = amount0 - deduct0;
        amount1AfterFee = amount1 - deduct1;
    }

    /**
     * @notice _netPerformanceAndOtherFees computes the fee share for manager as performance fee from the fee earned from pancake v3 pool.
     * @param rawFee0 fee earned in token0 from pancake v3 pool.
     * @param rawFee1 fee earned in token1 from pancake v3 pool.
     * @return fee0AfterDeduction fee in token0 earned after deducting performance fee from earned fee.
     * @return fee1AfterDeduction fee in token1 earned after deducting performance fee from earned fee.
     */
    function _netPerformanceAndOtherFees(
        DataTypes.State storage state,
        uint256 rawFee0,
        uint256 rawFee1
    ) private view returns (uint256 fee0AfterDeduction, uint256 fee1AfterDeduction) {
        uint256 _performanceFee = state.performanceFee;
        uint256 _otherFee = state.otherFee;
        uint256 deduct0 = ((rawFee0 * _performanceFee) / 10_000) + ((rawFee0 * _otherFee) / 10_000);
        uint256 deduct1 = ((rawFee1 * _performanceFee) / 10_000) + ((rawFee1 * _otherFee) / 10_000);
        fee0AfterDeduction = rawFee0 - deduct0;
        fee1AfterDeduction = rawFee1 - deduct1;
    }

    /**
     * @notice _updateTicks internal function to validate and update ticks
     * _lowerTick lower tick to update
     * _upperTick upper tick to update
     */
    function _updateTicks(
        DataTypes.State storage state,
        int24 _lowerTick,
        int24 _upperTick
    ) private {
        _validateTicks(state, _lowerTick, _upperTick);
        state.lowerTick = _lowerTick;
        state.upperTick = _upperTick;

        // Upon updating ticks inThePosition status is set to true.
        state.inThePosition = true;
        emit InThePositionStatusSet(true);
        emit TicksSet(_lowerTick, _upperTick);
    }

    /**
     * @notice _validateTicks validates the upper and lower ticks
     * @param _lowerTick lower tick to validate
     * @param _upperTick upper tick to validate
     */
    function _validateTicks(
        DataTypes.State storage state,
        int24 _lowerTick,
        int24 _upperTick
    ) private view {
        if (_lowerTick < TickMath.MIN_TICK || _upperTick > TickMath.MAX_TICK)
            revert VaultErrors.TicksOutOfRange();

        if (
            _lowerTick >= _upperTick ||
            _lowerTick % state.tickSpacing != 0 ||
            _upperTick % state.tickSpacing != 0
        ) revert VaultErrors.InvalidTicksSpacing();
    }

    /**
     * @notice internal function that pulls fee from the pool
     */
    function _pullFeeFromPool(DataTypes.State storage state) private {
        (, , uint256 fee0, uint256 fee1) = _withdraw(state, 0);
        _applyPerformanceAndOtherFee(state, fee0, fee1);
        (fee0, fee1) = _netPerformanceAndOtherFees(state, fee0, fee1);
        emit FeesEarned(fee0, fee1);
    }

    /**
     * @notice internal function that updates the fee percentages for both performance
     * and managing fee.
     * @param newManagingFee new managing fee to set.
     * @param newPerformanceFee new performance fee to set.
     */
    function _updateFees(
        DataTypes.State storage state,
        uint16 newManagingFee,
        uint16 newPerformanceFee,
        uint16 newOtherFee
    ) private {
        if (newManagingFee > MAX_MANAGING_FEE_BPS) revert VaultErrors.InvalidManagingFee();
        if (newPerformanceFee > MAX_PERFORMANCE_FEE_BPS) revert VaultErrors.InvalidPerformanceFee();

        if (state.inThePosition) _pullFeeFromPool(state);
        state.managingFee = newManagingFee;
        state.performanceFee = newPerformanceFee;
        state.otherFee = newOtherFee;
        emit FeesUpdated(newManagingFee, newPerformanceFee, newOtherFee);
    }
}

