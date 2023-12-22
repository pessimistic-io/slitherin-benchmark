pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ISwapRouter.sol";
import "./IUniswapV2.sol";
import "./IWETH.sol";
import "./IKobe.sol";


contract KobeArbitrage {
    address private constant SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address private constant SUSHI_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address private KOBE = address(0);
    address payable private TREASURY;
    address private constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNIV3_POOL = 0x641C00A822e8b671738d32a431a4Fb6074E5c79d;

    address private ethPair;
    address private usdtPair;

    event Profit(address indexed token, uint256 amount);

    constructor(address payable _treasury) {
        TREASURY = _treasury;
    }

    // https://github.com/Vectorized/solady/blob/6f724bd0f654b1199ee4cd909d206878c405bbcb/src/utils/FixedPointMathLib.sol
    /// @dev Returns the square root of `x`.
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // `floor(sqrt(2**15)) = 181`. `sqrt(2**15) - 181 = 2.84`.
            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // Let `y = x / 2**r`. We check `y >= 2**(k + 8)`
            // but shift right by `k` bits to ensure that if `x >= 256`, then `y >= 256`.
            let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffffff, shr(r, x))))
            z := shl(shr(1, r), z)

            // Goal was to get `z*z*y` within a small factor of `x`. More iterations could
            // get y in a tighter range. Currently, we will have y in `[256, 256*(2**16))`.
            // We ensured `y >= 256` so that the relative difference between `y` and `y+1` is small.
            // That's not possible if `x < 256` but we can just verify those cases exhaustively.

            // Now, `z*z*y <= x < z*z*(y+1)`, and `y <= 2**(16+8)`, and either `y >= 256`, or `x < 256`.
            // Correctness can be checked exhaustively for `x < 256`, so we assume `y >= 256`.
            // Then `z*sqrt(y)` is within `sqrt(257)/sqrt(256)` of `sqrt(x)`, or about 20bps.

            // For `s` in the range `[1/256, 256]`, the estimate `f(s) = (181/1024) * (s+1)`
            // is in the range `(1/2.84 * sqrt(s), 2.84 * sqrt(s))`,
            // with largest error when `s = 1` and when `s = 256` or `1/256`.

            // Since `y` is in `[256, 256*(2**16))`, let `a = y/65536`, so that `a` is in `[1/256, 256)`.
            // Then we can estimate `sqrt(y)` using
            // `sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2**18`.

            // There is no overflow risk here since `y < 2**136` after the first branch above.
            z := shr(18, mul(z, add(shr(r, x), 65536))) // A `mul()` is saved from starting `z` at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If `x+1` is a perfect square, the Babylonian method cycles between
            // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            z := sub(z, lt(div(x, z), z))
        }
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function imKobe() external {
        require(KOBE == address(0));
        KOBE = msg.sender;
        ethPair = IKobe(msg.sender).ethPair();
        usdtPair = IKobe(msg.sender).usdtPair();
    }

    function uniswapV2Call(address sender, uint, uint, bytes calldata data) external {
        require((msg.sender == ethPair || msg.sender == usdtPair) && sender == address(this));
        (bool usdtPairLoan, uint256 mustPay) = abi.decode(data, (bool, uint256));

        uint256 _tokenBal = IERC20(usdtPairLoan ? USDT : WETH).balanceOf(address(this));
        SafeERC20.safeApprove(IERC20(usdtPairLoan ? USDT : WETH), UNIV3_ROUTER, _tokenBal);
         ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdtPairLoan ? USDT : WETH,
                tokenOut: usdtPairLoan ? WETH : USDT,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _tokenBal,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
        });
        ISwapRouter(UNIV3_ROUTER).exactInputSingle(params);

        uint256 _assetBal = IERC20(!usdtPairLoan ? USDT : WETH).balanceOf(address(this));
        SafeERC20.safeApprove(IERC20(!usdtPairLoan ? USDT : WETH), SUSHI_ROUTER, _assetBal);
        address[] memory path = new address[](2);
        path[0] = !usdtPairLoan ? USDT : WETH;
        path[1] = KOBE;

        IUniswapV2Router(SUSHI_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _assetBal,
            0,
            path,
            address(this),
            block.timestamp
        );

        SafeERC20.safeTransfer(IERC20(KOBE), msg.sender, mustPay);
    }

    function doArbitrage() external {
        require(ethPair != address(0) && usdtPair != address(0));

        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3PoolState(UNIV3_POOL).slot0();
        uint256 usdtPerEth = uint256(sqrtPriceX96)**2 * 10**18 / (2**192);

        (uint256 kobeReserveEth, uint256 ethReserve, ) = IUniswapV2Pair(ethPair).getReserves();
        (uint256 kobeReserveUsdt, uint256 actualUsdtReserve, ) = IUniswapV2Pair(usdtPair).getReserves();

        if (KOBE > WETH) {
            uint256 _t = kobeReserveEth;
            kobeReserveEth = ethReserve;
            ethReserve = _t;
        }

        if (KOBE > USDT) {
            uint256 _t = kobeReserveUsdt;
            kobeReserveUsdt = actualUsdtReserve;
            actualUsdtReserve = _t;
        }
        
        uint256 usdtReserve = actualUsdtReserve * 10**18 / usdtPerEth;

        bool usdtPairLoan = false;
        uint256 ra;
        uint256 rb;
        uint256 rb1;
        uint256 rc;
        if ( (kobeReserveEth * 10**6 / ethReserve) > (kobeReserveUsdt * 10**6 / usdtReserve)) {
            usdtPairLoan = true;

            ra = kobeReserveUsdt;
            rb = usdtReserve;

            rb1 = ethReserve;
            rc = kobeReserveEth;
        } else {

            ra = kobeReserveEth;
            rb = ethReserve;

            rb1 = usdtReserve;
            rc = kobeReserveUsdt;
        }


        delete kobeReserveEth;
        delete ethReserve;
        delete kobeReserveUsdt;
        delete usdtReserve;

        uint256 _uDown = (rb1 * 1000 + rb * 997);
        uint256 ea = (ra * rb1 * 1000) / _uDown;
        uint256 eb = (rb * rc * 997) / _uDown;

        require(ea <= eb, "Arbitrage Impossible");
        uint256 optimalAmountIn = (sqrt(ea * eb * 997 * 1000) - (ea * 1000)) / 997;
        uint256 firstPairAmountOut = getAmountOut(optimalAmountIn, ra, usdtPairLoan ? uint256(actualUsdtReserve) : rb);

        IUniswapV2Pair(usdtPairLoan ? usdtPair : ethPair).swap(
            KOBE < (usdtPairLoan ? USDT : WETH) ? 0 : firstPairAmountOut,
            KOBE > (usdtPairLoan ? USDT : WETH) ? 0 : firstPairAmountOut,
            address(this),
            abi.encode(usdtPairLoan, optimalAmountIn)
        );
        IUniswapV2Pair(usdtPairLoan ? usdtPair : ethPair).skim(address(this));

        uint256 _tempBal = IERC20(KOBE).balanceOf(address(this));
        if (_tempBal > 0) {
            SafeERC20.safeTransfer(IERC20(KOBE), TREASURY, _tempBal);
            emit Profit(KOBE, _tempBal);
        }

        _tempBal = IERC20(USDT).balanceOf(address(this));
        if (_tempBal > 0) {
            SafeERC20.safeTransfer(IERC20(USDT), TREASURY, _tempBal);
            emit Profit(USDT, _tempBal);
        }

        _tempBal = IERC20(WETH).balanceOf(address(this));
        if (_tempBal > 0) {
            IWETH(WETH).withdraw(_tempBal);
        }

        _tempBal = address(this).balance;
        if (_tempBal > 0) {
            payable(TREASURY).transfer(_tempBal);
            emit Profit(address(0), _tempBal);
        }
        IKobe(KOBE).forceSwapBack();
    }

    receive() external payable {}
}
