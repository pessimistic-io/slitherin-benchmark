// SPDX-License-Identifier: MIT
// solhint-disable avoid-low-level-calls
pragma solidity >=0.8.0;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import "./IERC4626.sol";
import "./IQuoter.sol";
import "./UniV3Wrapper.sol";
import "./console.sol";

contract WrapperSwapper {
    using SafeTransferLib for ERC20;

    error ErrSwapFailed();
    error ErrTokenNotSupported(ERC20);

    address public immutable zeroXExchangeProxy;
    IQuoter public immutable quoter;

    constructor(
                address _zeroXExchangeProxy,
                address _quoter
    ) {
        zeroXExchangeProxy = _zeroXExchangeProxy;
        quoter = IQuoter(_quoter);
    }

    function swap(address inputToken, bytes calldata extraData)
        external returns (uint256 extraAmount, uint256 amountReturned) {

        (address vault,
         address toToken,
         address recipient,
         uint256 amountToMin,
         bool zeroForOne) = abi.decode(extraData, (address, address, address, uint256, bool));

        return this.swap(UniV3Wrapper(vault), ERC20(toToken), recipient, amountToMin, zeroForOne);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
    {
        if (amount0Delta > 0) {
            ERC20 token0 = ERC20(address(IUniV3Pool(msg.sender).token0()));
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20 token1 = ERC20(address(IUniV3Pool(msg.sender).token1()));
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    function _swap(IUniV3Pool pool, bool zeroForOne, uint256 amountIn, uint256 minimumAmountOut)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        (int256 a, int256 b) = pool.swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            bytes("")
        );
        if (zeroForOne) {
            amountOut = uint256(-b);
        } else {
            amountOut = uint256(-a);
        }
        require(amountOut >= minimumAmountOut);
    }

    function quote(
        UniV3Wrapper vault,
        uint256 amount,
        bool zeroForOne
    ) public returns (uint256 amountOut, uint256 amountTotal) {
        uint256 total = vault.totalSupply();

        IUniV3Pool pool = vault.pool();
        ERC20 token0 = ERC20(address(pool.token0()));
        ERC20 token1 = ERC20(address(pool.token1()));

        uint myLiquidity = uint256(vault.totalLiquidity()) * amount / total;

        (uint256 amount0, uint256 amount1) = vault.getAmountsForLiquidity(uint128(myLiquidity));

        amountOut = quoter.quoteExactInputSingle(
                                                 zeroForOne ? address(token0) : address(token1),
                                                 zeroForOne ? address(token1) : address(token0),
                                                 pool.fee(),
                                                 zeroForOne ? amount0 : amount1,
                                                 zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1
        );
        amountTotal = amountOut + (zeroForOne ? amount1 : amount0);
    }
           

    function swap(
        UniV3Wrapper vault,
        ERC20 toToken,
        address recipient,
        uint256 amountToMin,
        bool zeroForOne
    ) public returns (uint256 extraAmount, uint256 amountReturned) {
        uint256 amount = vault.balanceOf(address(this));

        amount = IERC4626(address(vault)).redeem(amount, address(this), address(this));

        IUniV3Pool pool = vault.pool();
        ERC20 token0 = ERC20(address(pool.token0()));
        ERC20 token1 = ERC20(address(pool.token1()));

        {

            uint256 balance0 = token0.balanceOf(address(this));
            uint256 balance1 = token1.balanceOf(address(this));
            
            _swap(pool, zeroForOne, zeroForOne ? balance0 : balance1, 0);

        }

        amountReturned = toToken.balanceOf(address(this));

        extraAmount = amountReturned - amountToMin;

        toToken.safeTransfer(recipient, amountReturned);
    }
}

