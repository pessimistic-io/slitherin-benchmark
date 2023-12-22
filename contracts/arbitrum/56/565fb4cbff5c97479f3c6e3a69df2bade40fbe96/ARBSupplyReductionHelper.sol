// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.15;

import "./INonfungiblePositionManager.sol";

interface IBobToken {
    function balanceOf(address user) external view returns (uint256);
    function approve(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IBobSwap {
    function admin() external view returns (address);
    function reclaim(address to, uint256 amount) external;
    function give(address token, uint256 amount) external;
    function farm(address token) external;
    function setCollateralFees(address token, uint64 inFee, uint64 outFee) external;
}

contract ARBSupplyReductionHelper {
    address constant positionManager = address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    uint256 constant tokenId1 = uint256(377468); // BOB/USDC
    address constant bob = address(0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B);
    address constant usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address constant usdt = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address constant bobSwap = address(0x72e6B59D4a90ab232e55D4BB7ed2dD17494D62fB);

    function step1() external {
        step2();

        (,,,,,,, uint128 liquidity1,,,,) = INonfungiblePositionManager(positionManager).positions(tokenId1);

        (uint256 amountBOB1, uint256 amountUSDC) = INonfungiblePositionManager(positionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(tokenId1, liquidity1 / 2, 0, 0, block.timestamp)
        );

        INonfungiblePositionManager(positionManager).collect(
            INonfungiblePositionManager.CollectParams(tokenId1, address(this), type(uint128).max, type(uint128).max)
        );

        IBobToken(bob).burn(amountBOB1);

        IBobToken(usdc).approve(bobSwap, amountUSDC);
        IBobSwap(bobSwap).give(usdc, amountUSDC);

        IBobSwap(bobSwap).setCollateralFees(usdc, 1 ether, 0);
        IBobSwap(bobSwap).setCollateralFees(usdt, 1 ether, 0);

        IBobSwap(bobSwap).farm(usdc);
        IBobSwap(bobSwap).farm(usdt);
    }

    function step2() public {
        uint256 bobBalance = IBobToken(bob).balanceOf(address(this));
        IBobSwap(bobSwap).reclaim(address(this), 5_000_000 ether);
        uint256 reclaimed = IBobToken(bob).balanceOf(address(this)) - bobBalance;
        IBobToken(bob).burn(reclaimed);
    }
}

