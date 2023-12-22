/* SPDX-License-Identifier: MIT */

/**
 *   @title YS
 */

pragma solidity =0.7.6;
pragma abicoder v2;

import "./YSRoles.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./IERC721Receiver.sol";
import "./INonfungiblePositionManager.sol";
import "./LiquidityManagement.sol";

contract YS is YSRoles {
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    uint256 public constant MAX_YS_FEE = 2500;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable poolFee;

    address public immutable ysTreasury;

    uint256 public maxTimeDelay = 15;

    constructor(
        address _admin,
        address _initialTrader,
        address _token0,
        address _token1,
        uint24 _poolFee,
        address _ysTreasury,
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _nonfungiblePositionManager
    ) YSRoles(_admin, _initialTrader) {
        token0 = _token0;
        token1 = _token1;
        poolFee = _poolFee;
        ysTreasury = _ysTreasury;

        swapRouter = _swapRouter;
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    // ----- Withdraw Functions -----

    function withdrawToken0(uint256 amount) public onlyOwner {
        if (amount == 0) {
            amount = IERC20(token0).balanceOf(address(this));
        }

        TransferHelper.safeTransfer(token0, _msgSender(), amount);
    }

    function withdrawToken1(uint256 amount) public onlyOwner {
        if (amount == 0) {
            amount = IERC20(token1).balanceOf(address(this));
        }

        TransferHelper.safeTransfer(token1, owner(), amount);
    }

    function withdraw(uint256 amount) public onlyOwner {
        if (amount == 0) {
            amount = address(this).balance;
        }

        TransferHelper.safeTransferETH(owner(), amount);
    }

    function withdrawNFT(uint256 tokenId) public onlyOwner {
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            owner(),
            tokenId
        );
    }

    // ----- Swap Functions -----

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 minAmountReceived,
        uint160 sqrtPriceLimitX96
    ) external onlyOwnerOrTrader returns (uint256 amountReceived) {
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + maxTimeDelay,
                amountIn: amount,
                amountOutMinimum: minAmountReceived,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });

        amountReceived = swapRouter.exactInputSingle(params);
    }

    // ----- Position Functions -----

    function mintPosition(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        int24 tickLower,
        int24 tickUpper
    )
        external
        onlyOwnerOrTrader
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        TransferHelper.safeApprove(
            token0,
            address(nonfungiblePositionManager),
            amount0Desired
        );
        TransferHelper.safeApprove(
            token1,
            address(nonfungiblePositionManager),
            amount1Desired
        );

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: block.timestamp + maxTimeDelay
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        onlyOwnerOrTrader
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp + maxTimeDelay
                });

        (liquidity, amount0, amount1) = nonfungiblePositionManager
            .increaseLiquidity(params);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) public onlyOwnerOrTrader returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: liquidity,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp + maxTimeDelay
                });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );
    }

    function collectFees(uint256 tokenId)
        public
        onlyOwnerOrTrader
        returns (uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    function burnNFT(uint256 tokenId) public onlyOwnerOrTrader {
        nonfungiblePositionManager.burn(tokenId);
    }

    function closePositionWithYSFee(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 ysFee
    )
        external
        onlyOwnerOrTrader
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 fee0,
            uint256 fee1,
            uint256 ysFee0,
            uint256 ysFee1
        )
    {
        require(ysFee <= MAX_YS_FEE, "YS fee too high");

        // Calculate the YS fee
        (fee0, fee1) = collectFees(tokenId);

        ysFee0 = (fee0 * ysFee) / 10000;
        ysFee1 = (fee1 * ysFee) / 10000;

        // Send the YS fee to the treasury
        TransferHelper.safeTransfer(token0, ysTreasury, ysFee0);
        TransferHelper.safeTransfer(token1, ysTreasury, ysFee1);

        // Close the position
        (amount0, amount1) = decreaseLiquidity(
            tokenId,
            liquidity,
            amount0Min,
            amount1Min
        );
        collectFees(tokenId);
        burnNFT(tokenId);
    }

    // ----- Configs -----

    function setMaxTimeDelay(uint256 newTimeDelay)
        public
        virtual
        onlyOwnerOrTrader
    {
        maxTimeDelay = newTimeDelay;
    }

    // ----- Receive Functions -----

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

