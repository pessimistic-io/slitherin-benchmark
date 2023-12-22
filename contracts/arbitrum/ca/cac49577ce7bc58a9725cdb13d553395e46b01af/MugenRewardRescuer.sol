// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// OpenZeppelin
import "./Ownable.sol";
import "./ERC20_IERC20.sol";

// Uniswap
import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";
import "./ISwapRouter.sol";

// Local utilities
import "./EscapeHatch.sol";

// Interfaces
import "./IMugenAutoCompounder.sol";

/// Operation: Save our ETH
contract MugenRewardRescuer is Ownable, EscapeHatch {
    // tokens
    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant MGN = IERC20(0xFc77b86F3ADe71793E1EEc1E7944DB074922856e);

    // UniswapV3
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public constant nftPositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3Pool public constant liquidityPool = IUniswapV3Pool(0xCe3dC36Cd501C00f643a09f2C8d9b69Fb941bB74);

    // Mugen
    IMugenAutoCompounder public constant autocompounder =
        IMugenAutoCompounder(0x44E4c3668552033419520bE229cD9DF0c35c4417);

    constructor() Ownable(msg.sender) {}

    function ticks() public view returns (int24 currentTick, int24 floorTick, int24 ceilTick, int24 tickSpacing) {
        // Current tick and tick spacing
        (, currentTick,,,,,) = liquidityPool.slot0();
        tickSpacing = liquidityPool.tickSpacing();

        // Given the current tick, get the floor and ceiling ticks for adding liquidity
        int24 flooredTickMultiplier = currentTick / tickSpacing;
        floorTick = flooredTickMultiplier * tickSpacing;
        ceilTick = (flooredTickMultiplier + 1) * tickSpacing;
    }

    function sellMugen(uint256 _mgnToSell) internal returns (uint256 amountOut) {
        MGN.approve(address(swapRouter), _mgnToSell);

        return swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(MGN),
                tokenOut: address(WETH),
                fee: 10_000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _mgnToSell,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function addSellSideLiquidity(uint256 _mgnToAdd)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        MGN.approve(address(nftPositionManager), _mgnToAdd);

        (, int24 floorTick,, int24 tickSpacing) = ticks();
        return nftPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(WETH),
                token1: address(MGN),
                fee: 10_000,
                tickLower: floorTick - tickSpacing,
                tickUpper: floorTick,
                amount0Desired: 0,
                amount1Desired: _mgnToAdd,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
    }

    function removeLiquidity(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        // Remove the principle
        (,,,,,,, uint128 liquidity,,,,) = nftPositionManager.positions(tokenId);
        nftPositionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // Collect fees
        (amount0, amount1) = nftPositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max, // Collect all owed token0
                amount1Max: type(uint128).max // Collect all owed token1
            })
        );

        // Burn the empty LP position
        nftPositionManager.burn(tokenId);
    }

    function rescue(uint256 mgnToSell, uint256 mgnToLP) external onlyOwner {
        // 0. Get MGN from the caller
        IERC20(MGN).transferFrom(msg.sender, address(this), mgnToSell + mgnToLP);

        // 1. Sell to push price down
        sellMugen(mgnToSell);
        // 2. Set up a sell wall
        (uint256 tokenId,,,) = addSellSideLiquidity(mgnToLP);
        // 3. Trigger the autocompounder buy
        autocompounder.compoundMGN();
        // 4. Remove liquidity
        removeLiquidity(tokenId);
        // 5. Send the remaining WETH and MGN back to the caller
        IERC20(WETH).transfer(msg.sender, IERC20(WETH).balanceOf(address(this)));
        IERC20(MGN).transfer(msg.sender, IERC20(MGN).balanceOf(address(this)));
        // 6. Assert that we've emptied the contract
        require(IERC20(WETH).balanceOf(address(this)) == 0, "WETH balance not 0");
        require(IERC20(MGN).balanceOf(address(this)) == 0, "MGN balance not 0");
    }
}

