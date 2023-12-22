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

    // simple EOA
    address public immutable treasury;
    IUniswapV3Pool public immutable pool;

    // the percent size of the range between ticks, rounded down
    // ex: a value of '10' means a 10% range between tickLower and tickUpper
    uint8 public window;
    // range of the window, in ticks
    int24 public tickUpper;
    int24 public tickLower;
    // timestamp of the last rebalance or re-range
    uint256 public lastRebalanceOrRerange;

    constructor(IUniswapV3Pool _pool, address _token0, address _token1, uint160 _slippageBps, address _treasury) ERC20("TidePool", "TPOOL") {
        pool = _pool;
        token0 = _token0 > _token1 ? _token1 : _token0;
        token1 = _token0 > _token1 ? _token0 : _token1;
        
        lastRebalanceOrRerange = block.timestamp;
        treasury = _treasury;
        slippageBps = _slippageBps;
        // window will self-optimize on deployment through rebalances.
        window = 1;

        // one-time approval to the Uniswap pool for max values, never rescinded
        TransferHelper.safeApprove(_token0, address(_pool), type(uint256).max);
        TransferHelper.safeApprove(_token1, address(_pool), type(uint256).max);
    }

    // Deposit any amount of token0 and token1 into the contract. The contract will perform the swap into the correct ratio and mint liquidity.
    function deposit(uint256 amount0, uint256 amount1) external override returns (uint128 liquidity) {
        require(amount0 > 0 || amount1 > 0, "NV");
        require(!locked,"L");

        // pull payment from the user. Requires an approval of both assets beforehand.
        if(amount0 > 0) pay(token0, msg.sender, address(this), amount0);
        if(amount1 > 0) pay(token1, msg.sender, address(this), amount1);

        (uint256 amount0In, uint256 amount1In) = swapIntoRatio(amount0, amount1);

        // harvest rewards and compound to prevent economic exploits
        (uint256 rewards0, uint256 rewards1) = harvest();
        if(rewards0 > 0 || rewards1 > 0) mintManagedLiquidity(rewards0, rewards1);

        (liquidity) = mintManagedLiquidity(amount0In, amount1In);
        require(liquidity > 0,"L0");

        // user is given TPOOL tokens to represent their share of the pool
        _mint(msg.sender, liquidity);
        emit Deposited(msg.sender, liquidity);
    }

    // Mint liquidity that will be owned by the contract. Assumes correct ratio! (As calculated in swapToRatio)
    // Assumes amount0Desired = amount1Desired for the range between tickLower and tickUpper at the current tick.
    // @param amount0Desired token0 amount that will go into liquidity.
    // @param amount0Desired token1 amount that will go into liquidity.
    function mintManagedLiquidity(uint256 amount0Desired, uint256 amount1Desired) private returns (uint128 liquidity) {
        // compute the liquidity amount. There'll be small amounts left over as the pool is always changing.
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, amount0Desired, amount1Desired);
        }

        if(liquidity > 0)
            pool.mint(address(this), tickLower, tickUpper, liquidity,  abi.encode(MintCallbackData({payer: address(this)})));
    }

    // Burn liquidity mangaged by the contract. Assumes the harvest() method was called first so rewards are properly calculated.
    function burnManagedLiquidity(uint128 amount) private returns (uint256 amount0, uint256 amount1) {
        require(amount > 0 && totalSupply() > 0,"NL");

        (uint256 float0, uint256 float1) = pool.burn(tickLower, tickUpper, amount);

        (amount0, amount1) = pool.collect(address(this), tickLower, tickUpper, float0.toUint128(), float1.toUint128());
    }

    // Withdraws managed liquidity for msg.sender. Burns all TPOOL tokens and distributes a percentage of the pool.
    function withdraw() external override {
        uint256 balance = balanceOf(msg.sender);
        require(balance > 0, "NB");

        (uint256 rewards0, uint256 rewards1) = harvest();

        uint256 userRewards0Share;
        uint256 userRewards1Share;

        // user share is a simple percentage of rewards, rounded down
        if(rewards0 > 0 || rewards1 > 0) {
           userRewards0Share = balance * rewards0 / totalSupply();
           userRewards1Share = balance * rewards1 / totalSupply();
        }

        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        (uint128 liquidity, , , , ) = pool.positions(positionKey);
        
        // user liquidity is a simple percentage of total supply, rounded down
        uint256 userLiquidityShare = balance * uint256(liquidity) / totalSupply();

        // burn liquidity proportial to user's share
        (uint256 amount0, uint256 amount1) = burnManagedLiquidity(userLiquidityShare.toUint128());
        _burn(msg.sender, balance);

        // compound any leftover rewards back into the pool
        mintManagedLiquidity(rewards0 - userRewards0Share, rewards1 - userRewards1Share);

        pay(token0, address(this), msg.sender, amount0 + userRewards0Share);
        pay(token1, address(this), msg.sender, amount1 + userRewards1Share) ;

        emit Withdraw(msg.sender, amount0, amount1);
    }
    
    // 
    function harvest() private returns (uint256 rewards0, uint256 rewards1) {
        if(totalSupply() == 0) {
            return (rewards0, rewards1);
        }
        // 0 burn "poke" to tell pool to recalculate rewards
        pool.burn(tickLower, tickUpper, 0);

        (rewards0, rewards1) = pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

        // remove fee of 10%, rounded down
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

    // Given any amount0 and any amount1, swap into the ratio given by the range tickLower and tickUpper
    // A convenience method for both the user and the contract
    function swapIntoRatio(uint256 amount0, uint256 amount1) private returns (uint256 desired0, uint256 desired1) {
        
        // desired will be a Ratio in the form of {n: X, d: 100 - X}
        TidePoolMath.Ratio memory desired;
        (,int24 tick,,,,,) = pool.slot0();

        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        (uint128 liquidity, , , , ) = pool.positions(positionKey);
        if(liquidity > 0) {
            // normalize the current range from 0 - 100 to give us our ratio
            desired.n = TidePoolMath.normalizeRange(tick, tickLower, tickUpper);
            desired.d = 100 - desired.n;                   
        } else {
            // create the range and save tickLower, tickUpper
            // it's possible to have a bias other than 50/50, but testing was inconclusive
            (tickUpper, tickLower) = TidePoolMath.calculateWindow(tick, pool.tickSpacing(), window, 50);
            desired.n = 50;
            desired.d = 50;
        }

        // calculate the difference between the current ratio of assets and the desired ratio such that current * delta = desired
        // ex: current = 60/40, desired = 50/50. While nominal difference is 10%, we need to swap only 5% of token1 to turn 60/40 into 50/50.
        (bool zeroForOne, TidePoolMath.Ratio memory delta) = TidePoolMath.calculateDeltaRatio(TidePoolMath.Ratio({n: amount0, d: amount1}), desired);

        uint256 amountIn;
        uint256 amountOut;

        if(zeroForOne) {
            amountIn = amount0 / delta.d * delta.n;           
            amountOut = swap(token0, token1, amountIn);
            desired0 = amount0 - amountIn;
            desired1 = amountOut + amount1;
        } else {
            amountIn = amount1 / delta.d * delta.n;              
            amountOut = swap(token1, token0, amountIn);
            desired0 = amountOut + amount0;
            desired1 = amount1 - amountIn;
        }
    }

    // standard Uniswap function
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn) private returns (uint256 amountOut) {
        bool zeroForOne = _tokenIn < _tokenOut;
        SwapCallbackData memory data = SwapCallbackData({zeroForOne: zeroForOne});

        (uint160 price,,,,,,) = pool.slot0();
        uint160 priceImpact = price * slippageBps / 1e6;
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
        locked = leftover > (_amountIn * slippageBps / 1e6) ? true : false;
    }

    // Reduces the range by 1% nominal. This function can be called a maximum of every 24 hours.
    // The purpose is to contract the range after expansion. This allows 1) more fees due to tighter range and 2) self-adjusting ranges to market conditions
    // Designed to be called by anyone.
    function rerange() external override {
        require(totalSupply() > 0, "NS");
        require((block.timestamp - lastRebalanceOrRerange) > 1 days, "1D");

        // harvest rewards (collecting fees), burn the rest of liquidity
        (uint256 rewards0, uint256 rewards1) = harvest();
        (uint256 amount0, uint256 amount1)= burnManagedLiquidity(type(uint128).max);

        // reduce the range by 1%. Safety checks happen in calculateWindow.
        window  -= 1;
        (,int24 tick,,,,,) = pool.slot0();

        // recalculate the range with the new window size, same ratio of assets  
        (tickUpper, tickLower) = TidePoolMath.calculateWindow(tick, pool.tickSpacing(), window, TidePoolMath.normalizeRange(tick, tickLower, tickUpper).toUint8());

        // include dust (tiny leftovers) gathered on the account
        (uint256 desired0, uint256 desired1) = swapIntoRatio(amount0 + rewards0 + IERC20(token0).balanceOf(address(this)), amount1 + rewards1 + IERC20(token1).balanceOf(address(this)));

        mintManagedLiquidity(desired0, desired1);

        lastRebalanceOrRerange = block.timestamp;
        emit Rerange();
    }

    // A rebalance is when we are out of range. We recalculate our position, swap into the correct ratios, and re-mint the position.
    // Designed to be called by anyone.
    function rebalance() external override {
        require(totalSupply() > 0, "NS");
        require(needsRebalance(), "IR");

        // collect rewards (and fees)
        (uint256 rewards0, uint256 rewards1) = harvest();

        // expand the window size by 2%. Safety checks happen in calculateWindow.
        window += 2;
        (uint256 amount0, uint256 amount1)= burnManagedLiquidity(type(uint128).max);

        // include dust (tiny amounts) gathered on the account
        (uint256 desired0, uint256 desired1) = swapIntoRatio(amount0 + rewards0 + IERC20(token0).balanceOf(address(this)), amount1 + rewards1 + IERC20(token1).balanceOf(address(this)));

        mintManagedLiquidity(desired0, desired1);
        
        lastRebalanceOrRerange = block.timestamp;
        emit Rebalance();
    }

    function needsRebalance() public view returns (bool) {
        (, int24 tick,,,,,) = pool.slot0();
        return tick > tickUpper || tick < tickLower;
    }

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        require(msg.sender == address(pool),"NP");
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        if (amount0Owed > 0) pay(token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0) pay(token1, decoded.payer, msg.sender, amount1Owed);
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(msg.sender == address(pool),"NP");
        require(amount0Delta > 0 || amount1Delta > 0,"NZ"); // swaps entirely within 0-liquidity regions are not supported
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
