// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "./LiquidityManager.sol";
import "./TestERC20.sol";

// mock class using NFTPool
contract LiquidityManagerMock is LiquidityManager {
    using SafeERC20 for IERC20;

    constructor(
        address pool, address token0_, address token1_, address feeRecipient, string memory name, string memory symbol,
        address poolDeployer, address swapRouter
    ) LiquidityManager(pool, token0_, token1_, feeRecipient, name, symbol, poolDeployer, swapRouter) {}

    function addLiquidity(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1, uint256[2] calldata inMin)
        external nonReentrant
    {
        _onlyAdmin();
        _settle(tickLower, tickUpper);
        _mintLiquidity(
            MintLiquidityData({
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: inMin[0],
                amount1Min: inMin[1]
            })
        );
    }

    function mockRanges(int24[4] calldata ranges_) external {
        ranges = ranges_;
    }

//    bool twapTickMocked;
//    int24 twapTick;
//    function mockTwapTick(int24 _twapTick) external {
//        twapTick = _twapTick;
//        twapTickMocked = true;
//    }

//    function getTwapTick(uint32 sec) public view override returns (int24) {
//        if(twapTickMocked) return twapTick;
//        return super.getTwapTick(sec);
//    }

    function mockTotalAmounts(uint256 total0, uint256 total1) external {
        token0.safeTransfer(0x000000000000000000000000000000000000dEaD, token0.balanceOf(address(this)));
        TestERC20(address(token0)).mint(address(this), total0);

        token1.safeTransfer(0x000000000000000000000000000000000000dEaD, token1.balanceOf(address(this)));
        TestERC20(address(token1)).mint(address(this), total1);
    }

    function priceAtTick(int24 tick) public view returns (uint256) {
        uint256 sqrt = TickMath.getSqrtRatioAtTick(tick);
        return FullMath.mulDiv(sqrt * sqrt, 1e18, 2**(96 * 2));
    }

    function currentPrice() external view returns (uint256){
        return priceAtTick(getCurrentTick());
    }
}

