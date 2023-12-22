/* SPDX-License-Identifier: MIT */

/**
 *   @title LL
 */

pragma solidity =0.7.6;
pragma abicoder v2;

import "./LLRoles.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./IERC721Receiver.sol";
import "./INonfungiblePositionManager.sol";
import "./LiquidityManagement.sol";

contract LL is LLRoles {
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    address public immutable WETH;
    address public immutable USDC;

    uint24 public constant poolFee = 500;

    uint256 public maxTimeDelay = 60;

    mapping(uint256 => uint256) public positions;

    constructor(
        address _admin,
        address _initialTrader,
        address _wethAddress,
        address _usdcAddress,
        ISwapRouter _swapRouter,
        INonfungiblePositionManager _nonfungiblePositionManager
    ) LLRoles(_admin, _initialTrader) {
        WETH = _wethAddress;
        USDC = _usdcAddress;

        swapRouter = _swapRouter;
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function withdrawETH(address to, uint256 amount) public onlyOwner {
        TransferHelper.safeTransferETH(to, amount);
    }

    function withdrawWETH(address to, uint256 amount) public onlyOwner {
        TransferHelper.safeTransfer(WETH, to, amount);
    }

    function withdrawUSDC(address to, uint256 amount) public onlyOwner {
        TransferHelper.safeTransfer(USDC, to, amount);
    }

    function withdrawPositionNFTBySlot(address to, uint256 slot)
        public
        onlyOwner
    {
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            to,
            positions[slot]
        );
        positions[slot] = 0;
    }

    function withdrawPositionNFT(address to, uint256 tokenId) public onlyOwner {
        nonfungiblePositionManager.safeTransferFrom(address(this), to, tokenId);
    }

    function burnPositionNFT(uint256 slot) public onlyOwner {
        nonfungiblePositionManager.burn(positions[slot]);
        positions[slot] = 0;
    }

    function updateSlot(uint256 slotId, uint256 tokenId)
        public
        onlyOwnerOrTrader
    {
        positions[slotId] = tokenId;
    }

    function setMaxTimeDelay(uint256 newTimeDelay)
        public
        virtual
        onlyOwnerOrTrader
    {
        maxTimeDelay = newTimeDelay;
    }

    function buyUSDC(uint256 amountETH, uint256 minAmountUSDC)
        external
        onlyOwnerOrTrader
        returns (uint256 amountUSDC)
    {
        TransferHelper.safeApprove(WETH, address(swapRouter), amountETH);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + maxTimeDelay,
                amountIn: amountETH,
                amountOutMinimum: minAmountUSDC,
                sqrtPriceLimitX96: 0
            });

        amountUSDC = swapRouter.exactInputSingle(params);
    }

    function buyETH(uint256 amountUSDC, uint256 minAmountETH)
        external
        onlyOwnerOrTrader
        returns (uint256 amountETH)
    {
        TransferHelper.safeApprove(USDC, address(swapRouter), amountUSDC);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + maxTimeDelay,
                amountIn: amountUSDC,
                amountOutMinimum: minAmountETH,
                sqrtPriceLimitX96: 0
            });

        amountETH = swapRouter.exactInputSingle(params);
    }

    function mintPosition(
        uint256 slot,
        uint256 amountToMintETH,
        uint256 amountToMintUSDC,
        int24 tickLower,
        int24 tickUpper
    )
        external
        onlyOwnerOrTrader
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amountETH,
            uint256 amountUSDC
        )
    {
        require(positions[slot] == 0, "Slot not empty");

        TransferHelper.safeApprove(
            WETH,
            address(nonfungiblePositionManager),
            amountToMintETH
        );
        TransferHelper.safeApprove(
            USDC,
            address(nonfungiblePositionManager),
            amountToMintUSDC
        );

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: WETH,
                token1: USDC,
                fee: poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amountToMintETH,
                amount1Desired: amountToMintUSDC,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + maxTimeDelay
            });

        (tokenId, liquidity, amountETH, amountUSDC) = nonfungiblePositionManager
            .mint(params);

        positions[slot] = tokenId;
    }

    function collectFees(uint256 tokenId)
        external
        onlyOwnerOrTrader
        returns (uint256 amountETH, uint256 amountUSDC)
    {
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amountETH, amountUSDC) = nonfungiblePositionManager.collect(params);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 newLiquidity,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        onlyOwnerOrTrader
        returns (uint256 amountETH, uint256 amountUSDC)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: newLiquidity,
                    amount0Min: amount0Min,
                    amount1Min: amount1Min,
                    deadline: block.timestamp + maxTimeDelay
                });

        (amountETH, amountUSDC) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amountAddETH,
        uint256 amountAddUSDC
    )
        external
        onlyOwnerOrTrader
        returns (
            uint128 liquidity,
            uint256 amountETH,
            uint256 amountUSDC
        )
    {
        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amountAddETH,
                    amount1Desired: amountAddUSDC,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + maxTimeDelay
                });

        (liquidity, amountETH, amountUSDC) = nonfungiblePositionManager
            .increaseLiquidity(params);
    }

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

