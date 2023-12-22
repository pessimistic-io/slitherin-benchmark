// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.1;

import "./TickMath.sol";
import "./console.sol";

pragma experimental ABIEncoderV2;

interface IUniswapRouter {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
}

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapFactoryV3 {
    function createAndInitializePoolIfNecessary(
    address tokenA,
    address tokenB,
    uint24 fee,
    uint160 sqrtPriceX96
  ) external returns (address pool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    function mint(MintParams calldata params) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


contract UniswapV3LiquidityAdder is IERC721Receiver{
    IERC20 public token0;
    IERC20 public token1;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    
    constructor(address _token0, address _token1, INonfungiblePositionManager _nonfungiblePositionManager) {
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(nonfungiblePositionManager), 'not a univ3 nft');
        return this.onERC721Received.selector;
    }

    function mintNewPosition()
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {

        uint256 amount0ToMint = token0.balanceOf(msg.sender);
        uint256 amount1ToMint = token1.balanceOf(msg.sender);

        token0.transferFrom(msg.sender, address(this), amount0ToMint);
        token1.transferFrom(msg.sender, address(this), amount1ToMint);

        // Approve the position manager
        token0.approve(address(nonfungiblePositionManager), amount0ToMint);
        token1.approve(address(nonfungiblePositionManager), amount1ToMint);

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: 3000,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp + 10000
            });

        console.log("before adding");
        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
        // (tokenId, liquidity, amount0, amount1) = (0, 0 ,0 ,0);
        console.log("after adding");

        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            token0.approve(address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            token0.transfer(msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            token1.approve(address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            token1.transfer(msg.sender, refund1);
        }
    }
}
