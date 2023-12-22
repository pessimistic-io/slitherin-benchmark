//SPDX-License-Identifier: Unlicense
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ITidePool.sol";
import "./TidePoolMath.sol";
import "./SafeCast.sol";
import "./ERC20.sol";
import "./TickMath.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3MintCallback.sol";
import "./IUniswapV3SwapCallback.sol";
import "./PositionKey.sol";
import "./TransferHelper.sol";
import "./LiquidityAmounts.sol";

contract TidePool is ITidePool, IUniswapV3MintCallback, IUniswapV3SwapCallback, ERC20 {

    using SafeCast for uint256;

    // ERC20 tokens for pools
    // token0 < token1, just like the pool address order in Uniswap
    address public immutable token0;
    address public immutable token1;

    // amount of acceptable slippage in basis points: > 0 && < 1e6
    uint160 public immutable slippageBps;
    // deposits will be prevented if a swap goes over slippageBps. It will unlock after a rebalance below slippageBps.
    // users can always withdraw. the locking prevents the system from getting too large for the pool and being eaten by slippage.
    bool public locked;

    address public immutable treasury;
    IUniswapV3Pool public immutable pool;

    // Number of ticks between tickUpper and tickLower
    int24 public tickWindow;
    // limits of the range
    int24 public tickUpper;
    int24 public tickLower;
    // timestamp of the last rebalance or re-range
    uint256 public lastRebalanceOrRerange;

    constructor(IUniswapV3Pool _pool, uint160 _slippageBps, int24 _tickWindow, address _treasury) ERC20("TidePool", "TPOOL") {
        pool = _pool;
        token0 = _pool.token0();
        token1 = _pool.token1();
        
        lastRebalanceOrRerange = block.timestamp;
        treasury = _treasury;
        slippageBps = _slippageBps;
        tickWindow = _tickWindow;

        // one-time approval to the Uniswap pool for max values, never rescinded
        TransferHelper.safeApprove(_pool.token0(), address(_pool), type(uint256).max);
        TransferHelper.safeApprove(_pool.token1(), address(_pool), type(uint256).max);
    }

    // Deposit any amount of token0 and token1 into the contract. The contract will perform the swap into the correct ratio and mint liquidity.
    function deposit(uint256 amount0, uint256 amount1) external override returns (uint128 liquidity) {
        require(amount0 > 0 || amount1 > 0, "V");
        require(!locked,"L");

        // harvest rewards and compound to prevent economic exploits
        (uint256 rewards0, uint256 rewards1) = harvest();
        if(rewards0 > 0 || rewards1 > 0) mintManagedLiquidity(rewards0, rewards1);

        // pull payment from the user. Requires an approval of both assets beforehand.
        if(amount0 > 0) pay(token0, msg.sender, address(this), amount0);
        if(amount1 > 0) pay(token1, msg.sender, address(this), amount1);

        (uint256 amount0In, uint256 amount1In) = swapIntoRatio(amount0, amount1);

        (liquidity) = mintManagedLiquidity(amount0In, amount1In);
        require(liquidity > 0,"L0");

        // user is given TPOOL tokens to represent their share of the pool
        _mint(msg.sender, liquidity);

        // refund leftover amounts that weren't minted
        refund(liquidity, amount0, amount1);
        
        emit Deposited(msg.sender, amount0, amount1);
    }

    function refund(uint128 liquidity, uint256 amount0, uint256 amount1) internal {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();

        (uint256 used0, uint256 used1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, 
            TickMath.getSqrtRatioAtTick(tickLower), 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            liquidity);

        uint256 leftover0 = amount0 - used0;
        uint256 leftover1 = amount1 - used1;

        uint256 t0 = IERC20(token0).balanceOf(address(this));
        uint256 t1 = IERC20(token1).balanceOf(address(this));

        if(leftover0 > 0) pay(token0, address(this), msg.sender, leftover0 > t0 ? t0 : leftover0);
        if(leftover1 > 0) pay(token1, address(this), msg.sender, leftover1 > t1 ? t1 : leftover1);
    }

    // Mint liquidity that will be owned by the contract. Assumes correct ratio! (As calculated in swapToRatio)
    // Assumes amount0Desired = amount1Desired for the range between tickLower and tickUpper at the current tick.
    // @param amount0Desired token0 amount that will go into liquidity.
    // @param amount0Desired token1 amount that will go into liquidity.
    function mintManagedLiquidity(uint256 amount0Desired, uint256 amount1Desired) private returns (uint128 liquidity) {
        // compute the liquidity amount. There'll be small amounts left over as the pool is always changing.
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, 
            TickMath.getSqrtRatioAtTick(tickLower), 
            TickMath.getSqrtRatioAtTick(tickUpper), 
            amount0Desired, 
            amount1Desired
        );

        if(liquidity > 0)
            pool.mint(address(this), tickLower, tickUpper, liquidity,  abi.encode(MintCallbackData({payer: address(this)})));
    }

    // Burn liquidity mangaged by the contract. Assumes the harvest() method was called first so rewards/fees are properly calculated.
    function burnManagedLiquidity(uint128 amount) private returns (uint256 amount0, uint256 amount1) {
        require(amount > 0 && totalSupply() > 0,"I");

        (uint256 float0, uint256 float1) = pool.burn(tickLower, tickUpper, amount);

        (amount0, amount1) = pool.collect(address(this), tickLower, tickUpper, float0.toUint128(), float1.toUint128());
    }

    // Withdraws managed liquidity for msg.sender. Burns all TPOOL tokens and distributes a percentage of the pool.
    function withdraw() external override {
        uint256 balance = balanceOf(msg.sender);
        require(balance > 0, "B");

        (uint256 rewards0, uint256 rewards1) = harvest();

        // user share is a simple percentage of rewards
        uint256 userRewards0Share = balance * rewards0 / totalSupply();
        uint256 userRewards1Share = balance * rewards1 / totalSupply();
        
        // user liquidity is a simple percentage of total supply
        uint256 userLiquidityShare = balance * uint256(getPosition()) / totalSupply();

        // burn liquidity proportial to user's share
        (uint256 amount0, uint256 amount1) = burnManagedLiquidity(userLiquidityShare.toUint128());
        _burn(msg.sender, balance);

        // compound any leftover rewards back into the pool
        mintManagedLiquidity(rewards0 - userRewards0Share, rewards1 - userRewards1Share);

        pay(token0, address(this), msg.sender, amount0 + userRewards0Share);
        pay(token1, address(this), msg.sender, amount1 + userRewards1Share) ;

        emit Withdraw(msg.sender, amount0, amount1);
    }
    
    function harvest() private returns (uint256 rewards0, uint256 rewards1) {
        if(totalSupply() == 0) {
            return (rewards0, rewards1);
        }
        // 0 burn "poke" to tell pool to recalculate rewards
        pool.burn(tickLower, tickUpper, 0);

        (rewards0, rewards1) = pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

        // remove fee of 10%
        uint256 fees0 = rewards0 * 10 / 100;
        uint256 fees1 = rewards1 * 10 / 100;

        // if there are rewards, we send the protocol's fees to the treasury
        if(fees0 > 0 && fees1 > 0) {
            rewards0 -= fees0;
            rewards1 -= fees1;

            pay(token0, address(this), treasury, fees0);
            pay(token1, address(this), treasury, fees1);
        }

        // reward amounts are sent back to the calling function
    }

    // given amount0 and amount1, how much is useable RIGHT NOW as liquidity? We need this to calculate leftovers for swapping.
    function getUsableLiquidity(uint160 sqrtRatioX96, uint256 amount0, uint256 amount1) private view returns (uint256, uint256) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint128 liquidityAmounts = LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
        return LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidityAmounts);
    }

    // Given any amount0 and any amount1, swap into the ratio given by the range tickLower and tickUpper
    function swapIntoRatio(uint256 amount0, uint256 amount1) private returns (uint256 desired0, uint256 desired1) {
        
        (uint160 sqrtRatioX96,int24 tick,,,,,) = pool.slot0();

        uint256 amountIn;
        uint256 amountOut;

        if(getPosition() == 0)
            (tickUpper, tickLower) = TidePoolMath.calculateWindow(tick, pool.tickSpacing(), tickWindow, 50);

        // 1) calculate how much liquidity we can generate with what we're given
        (uint256 useable0, uint256 useable1) = getUsableLiquidity(sqrtRatioX96, amount0, amount1);

        // 2) swap the leftover tokens into a ratio to maximimze the liquidity we can mint
        // TidePoolMath.normalizeRange(tick, tickLower, tickUpper) will return a number from 0-100
        // This is a measure of where tick is in relation to the the upper and lower parts of the range
        // The ratio of token0:token1 will be n:(100-n)
        uint256 n = TidePoolMath.normalizeRange(tick, tickLower, tickUpper);

        if(TidePoolMath.proportion(amount0, useable0, amount1, useable1)) {
            amountIn = (amount0 - useable0) * n / 100;
            
            // corner case where we already have correct ratio and don't need to swap
            if(amountIn > 0) amountOut = swap(token0, token1, amountIn);

            desired0 = amount0 - amountIn;
            desired1 = amountOut + amount1;
        } else {
            amountIn = (amount1 - useable1) * (100-n) / 100;
            
            // corner case where we already have correct ratio and don't need to swap
            if(amountIn > 0)  amountOut = swap(token1, token0, amountIn);

            desired1 = amount1 - amountIn;
            desired0 = amountOut + amount0;
        }
    }

    // standard Uniswap function
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn) private returns (uint256 amountOut) {
        bool zeroForOne = _tokenIn < _tokenOut;
        SwapCallbackData memory data = SwapCallbackData({zeroForOne: zeroForOne});

        (uint160 price,,,,,,) = pool.slot0();
        uint160 priceImpact = price * slippageBps / 1e5;
        uint160 sqrtPriceLimitX96 = zeroForOne ? price - priceImpact : price + priceImpact;

        (int256 amount0, int256 amount1) =
            pool.swap(
                address(this),
                zeroForOne,
                _amountIn.toInt256(),
                sqrtPriceLimitX96,
                abi.encode(data)
            );

        amountOut = uint256(-(zeroForOne ? amount1 : amount0));

        // If we have excess _amountIn, that means there's too much slippage for the pool size. Lock deposits. Unlock them if we're below this level.
        uint256 leftover = zeroForOne ? _amountIn - uint256(amount0) : _amountIn - uint256(amount1);
    
        locked = leftover > (_amountIn * slippageBps / 1e5) ? true : false;
    }

    // Reduces the range by 1 tick per day. This function can be called a maximum of every 24 hours.
    // The purpose is to contract the range after expansion.
    // This allows 1) more fees due to tighter range and 2) self-adjusting ranges to market conditions.
    // Designed to be called by anyone.
    function rerange() external override {
        uint256 diff = block.timestamp - lastRebalanceOrRerange;
        require(totalSupply() > 0);
        require(diff > 1 days);

        // harvest rewards (collecting fees), burn the rest of liquidity
        harvest();

        // get current liquidity and burn it
        burnManagedLiquidity(getPosition());

        // reduce the range by 1 tick per day since the lastRebalanceOrRerange 
        // Safety checks happen in calculateWindow.
        tickWindow  -= int24(diff / 1 days);
        (,int24 tick,,,,,) = pool.slot0();

        // recalculate the range with the new window size, same ratio of assets  
        (tickUpper, tickLower) = TidePoolMath.calculateWindow(tick, pool.tickSpacing(), tickWindow, TidePoolMath.normalizeRange(tick, tickLower, tickUpper).toUint8());

        // include dust (tiny leftovers) gathered on the account
        (uint256 desired0, uint256 desired1) = swapIntoRatio(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));

        mintManagedLiquidity(desired0, desired1);

        lastRebalanceOrRerange = block.timestamp;
        emit Rerange();
    }

    // A rebalance is when we are out of range. We recalculate our position, swap into the correct ratios, and re-mint the position.
    // Designed to be called by anyone.
    function rebalance() external override {
        require(totalSupply() > 0);
        require(needsRebalance());

        // collect rewards and fees
        harvest();

        // get current liquidity and burn it
        burnManagedLiquidity(getPosition());

        (uint256 desired0, uint256 desired1) = swapIntoRatio(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));

        // expand the window size by 4 ticks. Safety checks happen in calculateWindow.
        tickWindow += 4;
        (, int24 tick,,,,,) = pool.slot0();
        (tickUpper, tickLower) = TidePoolMath.calculateWindow(tick, pool.tickSpacing(), tickWindow, 50);
        mintManagedLiquidity(desired0, desired1);
        
        lastRebalanceOrRerange = block.timestamp;
        emit Rebalance();
    }

    function needsRebalance() public view returns (bool) {
        (, int24 tick,,,,,) = pool.slot0();
        return tick > tickUpper || tick < tickLower;
    }

    function getPosition() public view returns (uint128 liquidity) {
        (liquidity, , , , ) = pool.positions(PositionKey.compute(address(this), tickLower, tickUpper));
        return liquidity;
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        require(msg.sender == address(pool),"P");
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        if (amount0Owed > 0) pay(token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(token1, decoded.payer, msg.sender, amount1Owed);
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(msg.sender == address(pool),"P");
        require(amount0Delta > 0 || amount1Delta > 0,"Z"); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        
        if(data.zeroForOne) {
            pay(token0, address(this), msg.sender, uint256(amount0Delta));
        } else {
            pay(token1, address(this), msg.sender, uint256(amount1Delta));
        }
    }

    function pay(address token, address payer, address recipient, uint256 value) private {
        if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
