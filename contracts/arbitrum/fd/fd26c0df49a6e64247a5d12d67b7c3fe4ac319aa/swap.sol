// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./IERC20.sol";

interface IRamsesV2Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract fixoor {
    uint256 unlocked;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;

    constructor() {
        unlocked = 1;
    }

    function ramsesV2SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        (address pool, address tokenIn) = abi.decode(data, (address, address));
        require(msg.sender == pool, "!pool");
        require(unlocked == 2);

        if (amount0Delta > 0) {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount0Delta));
        } else {
            IERC20(tokenIn).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        bool zeroForOne,
        uint256 amountIn
    ) external {
        unlocked = 2;
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        int256 amount = int256(amountIn);
        if (zeroForOne) {
            (, amount) = IRamsesV2Pool(pool).swap(
                address(this),
                zeroForOne,
                amount < 0 ? -amount : amount,
                MIN_SQRT_RATIO + 1,
                abi.encode(pool, tokenIn)
            );
        } else {
            (amount, ) = IRamsesV2Pool(pool).swap(
                address(this),
                zeroForOne,
                amount < 0 ? -amount : amount,
                MAX_SQRT_RATIO - 1,
                abi.encode(pool, tokenIn)
            );
        }

        uint256 amountOut = uint256(-amount);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        unlocked = 1;
    }
}

