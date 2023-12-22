// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import {Strings} from "./Strings.sol";

import "./IMellowToken.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

import "./FullMath.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./PositionValue.sol";
import "./OracleLibrary.sol";

import "./UniV3TokenRegistry.sol";

contract UniV3Token is IERC20, Context, IERC20Metadata, IMellowToken {
    using SafeERC20 for IERC20;
    error InvalidConstructorParams();
    error TokenAlreadyInitialized();
    error UnstablePool();

    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;
    ISwapRouter public immutable router;
    UniV3TokenRegistry public immutable registry;

    uint32 public constant AVERAGE_TICK_TIMESPAN = 60; // seconds
    uint256 public constant MAX_FEES_SWAP_SLIPPAGE = 1 * 10 ** 7; // 5%
    uint256 public constant DENOMINATOR = 10 ** 9;
    uint256 public constant Q96 = 2 ** 96;

    bool public initialized;
    address public token0;
    address public token1;
    uint24 public fee;
    int24 public tickLower;
    int24 public tickUpper;

    uint160 public sqrtLowerPriceX96;
    uint160 public sqrtUpperPriceX96;

    IUniswapV3Pool public pool;
    uint256 public uniV3Nft;

    // ERC20 Openzeppelin source
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_, UniV3TokenRegistry registry_) {
        positionManager = positionManager_;
        factory = IUniswapV3Factory(positionManager.factory());
        router = router_;
        registry = registry_;
    }

    function convertLiquidityToSupply(uint256 liquidity) public view returns (uint256 supply) {
        (, , , , , , , uint128 totalLiquidity, , , , ) = positionManager.positions(uniV3Nft);
        supply = FullMath.mulDiv(liquidity, _totalSupply, totalLiquidity);
    }

    function convertSupplyToLiquidity(uint256 supply) public view returns (uint128 liquidity) {
        (, , , , , , , uint128 totalLiquidity, , , , ) = positionManager.positions(uniV3Nft);
        liquidity = uint128(FullMath.mulDiv(supply, totalLiquidity, _totalSupply));
    }

    function getAmountsForLiquidity(uint128 liquidity) public view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtLowerPriceX96,
            sqrtUpperPriceX96,
            liquidity
        );
    }

    function isReplaceable(address token) public view override returns (bool) {
        uint256 tokenId = registry.ids(token);
        return
            tokenId != 0 &&
            UniV3Token(token).token0() == token0 &&
            UniV3Token(token).token1() == token1 &&
            UniV3Token(token).fee() == fee;
    }

    function equals(address token) public view override returns (bool) {
        return
            isReplaceable(token) &&
            UniV3Token(token).tickLower() == tickLower &&
            UniV3Token(token).tickUpper() == tickUpper;
    }

    function initialize(bytes calldata data) external {
        if (initialized) revert TokenAlreadyInitialized();
        (token0, token1, fee, tickLower, tickUpper, _name, _symbol) = abi.decode(
            data,
            (address, address, uint24, int24, int24, string, string)
        );
        pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));

        IERC20(token0).safeApprove(address(positionManager), type(uint256).max);
        IERC20(token1).safeApprove(address(positionManager), type(uint256).max);
        IERC20(token0).safeApprove(address(router), type(uint256).max);
        IERC20(token1).safeApprove(address(router), type(uint256).max);

        uint256 minAmount0 = 10 ** (IERC20Metadata(token0).decimals() / 2);
        uint256 minAmount1 = 10 ** (IERC20Metadata(token1).decimals() / 2);
        uint256 usedAmount0 = 0;
        uint256 usedAmount1 = 0;
        IERC20(token0).safeTransferFrom(msg.sender, address(this), minAmount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), minAmount1);

        (uniV3Nft, _totalSupply, usedAmount0, usedAmount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: minAmount0,
                amount1Desired: minAmount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1
            })
        );
        {
            minAmount0 -= usedAmount0;
            if (minAmount0 > 0) IERC20(token0).safeTransfer(msg.sender, minAmount0);
        }
        {
            minAmount1 -= usedAmount1;
            if (minAmount1 > 0) IERC20(token1).safeTransfer(msg.sender, minAmount1);
        }
        sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function mint(uint256 amount0, uint256 amount1, uint256 minLpAmount) external {
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        (, , , , , , , uint128 totalLiquidity, , , , ) = positionManager.positions(uniV3Nft);

        (uint128 actualLiquidity, uint256 used0, uint256 used1) = positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: uniV3Nft,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1
            })
        );

        uint256 lpAmount = FullMath.mulDiv(actualLiquidity, _totalSupply, totalLiquidity);
        require(lpAmount >= minLpAmount, "Limit underflow");

        if (amount0 > used0) IERC20(token0).safeTransfer(msg.sender, amount0 - used0);
        if (amount1 > used1) IERC20(token1).safeTransfer(msg.sender, amount1 - used1);

        _mint(msg.sender, lpAmount);
    }

    function burn(uint256 lpAmount) external {
        if (lpAmount == 0) return;
        uint128 liquidity = convertSupplyToLiquidity(lpAmount);
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: uniV3Nft,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1
            })
        );

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: msg.sender,
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );

        _burn(msg.sender, lpAmount);
    }

    function calculateTargetRatioOfToken1(
        uint160 sqrtSpotPriceX96,
        uint256 spotPriceX96
    ) public view returns (uint256 targetRatioOfToken1X96) {
        if (sqrtLowerPriceX96 >= sqrtSpotPriceX96) {
            return 0;
        } else if (sqrtUpperPriceX96 <= sqrtSpotPriceX96) {
            return Q96;
        }

        uint256 x = FullMath.mulDiv(
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            Q96,
            FullMath.mulDiv(sqrtSpotPriceX96, sqrtUpperPriceX96, Q96)
        );
        uint256 y = sqrtSpotPriceX96 - sqrtLowerPriceX96;
        targetRatioOfToken1X96 = FullMath.mulDiv(y, Q96, FullMath.mulDiv(x, spotPriceX96, Q96) + y);
    }

    function calculateAmountsForSwap(
        uint256[2] memory currentAmounts,
        uint256 priceX96,
        uint256 targetRatioOfToken1X96
    ) public view returns (uint256 tokenInIndex, uint256 amountIn) {
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(pool.fee()), 10 ** 6);

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, currentAmounts[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, currentAmounts[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
        if (amountIn > currentAmounts[tokenInIndex]) {
            amountIn = currentAmounts[tokenInIndex];
        }
    }

    function _swapToTarget(uint160 sqrtPriceX96, uint256[2] memory currentAmounts) private {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        (uint256 tokenInIndex, uint256 amountIn) = calculateAmountsForSwap(
            currentAmounts,
            priceX96,
            calculateTargetRatioOfToken1(sqrtPriceX96, priceX96)
        );

        address tokenIn = token0;
        address tokenOut = token1;
        if (tokenInIndex == 1) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            (tokenIn, tokenOut) = (tokenOut, tokenIn);
        }

        uint256 expectedAmountOut = FullMath.mulDiv(
            FullMath.mulDiv(priceX96, DENOMINATOR - MAX_FEES_SWAP_SLIPPAGE, DENOMINATOR),
            amountIn,
            Q96
        );

        if (
            amountIn < 10 ** ((IERC20Metadata(tokenIn).decimals() / 2)) ||
            expectedAmountOut < 10 ** ((IERC20Metadata(tokenOut).decimals() / 2))
        ) {
            // insufficient amount for rebalance
            return;
        }

        router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: expectedAmountOut,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // ~300k
    function compound() external {
        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uint256 fee0 = IERC20(token0).balanceOf(address(this));
        uint256 fee1 = IERC20(token1).balanceOf(address(this));

        if (fee0 + fee1 == 0) return;

        (int24 averageTick, , bool withFail) = OracleLibrary.consult(address(pool), AVERAGE_TICK_TIMESPAN);
        if (withFail) {
            revert UnstablePool();
        }
        uint160 averageSqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        _swapToTarget(averageSqrtPriceX96, [fee0, fee1]);

        positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: uniV3Nft,
                amount0Desired: IERC20(token0).balanceOf(address(this)),
                amount1Desired: IERC20(token1).balanceOf(address(this)),
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1
            })
        );
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

