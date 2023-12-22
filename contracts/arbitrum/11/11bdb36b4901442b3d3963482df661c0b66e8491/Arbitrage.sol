// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import{IERC20} from "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import{IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import{PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import{ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import{IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import{IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

contract Arbitrage {

  address payable owner;

  address private constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  ISwapRouter private constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
  IQuoter private constant qouter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
  IUniswapV2Router01 private constant sushiswapRouter = IUniswapV2Router01(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);


  address private constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
  address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address private constant LINK = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

  IERC20 private constant weth = IERC20(WETH);
  IERC20 private constant link = IERC20(LINK);

  uint24 private constant POOL_FEE = 500;

  struct FlashData {
      uint wethAmount;
      address caller;
  }

  IUniswapV3Pool private immutable pool;

  constructor() {
      // Code
    owner = payable(msg.sender);

    PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(
        USDC,
        WETH,
        POOL_FEE
    );
    pool = IUniswapV3Pool(PoolAddress.computeAddress(FACTORY, poolKey));
  }


  function flash(uint wethAmount) external {
      // Code
      bytes memory data = abi.encode(
          FlashData({wethAmount: wethAmount, caller: msg.sender})
      );
      pool.flash(address(this), 0, wethAmount, data);
  }

  function uniswapV3FlashCallback(
      uint fee0,
      uint fee1,
      bytes calldata data
  ) external {
      // Code
      require(msg.sender == address(pool), "not authorized");

      FlashData memory decoded = abi.decode(data, (FlashData));
      //code here
      weth.approve(address(router), decoded.wethAmount);
      uint amountOutMin = qouter.quoteExactInputSingle(
        WETH,
        LINK,
        3000,
        decoded.wethAmount,
        0
      );

      ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
        .ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: LINK,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: decoded.wethAmount,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });
      uint linkAmount = router.exactInputSingle(params);

      require(linkAmount > 0, "Abort transaction: Trade returned zero");

      link.approve(address(sushiswapRouter), linkAmount);
      address[] memory path = new address [](2);
      path[0] = LINK;
      path[1] = WETH;

      uint minimumTokens = sushiswapRouter.getAmountsOut(
        linkAmount,
        path
      )[1];

      sushiswapRouter.swapExactTokensForTokens(
        linkAmount,
        minimumTokens,
        path,
        address(this),
        block.timestamp
      )[1];

      weth.transferFrom(decoded.caller, address(this), fee1);
      weth.transfer(address(pool), decoded.wethAmount + fee1);
  }

  function withdraw() external onlyOwner {
    weth.transfer(msg.sender, weth.balanceOf(address(this)));
  }

  modifier onlyOwner() {
      require(
          msg.sender == owner,
          "Only the contract owner can call this function"
      );
      _;
  }

  receive() external payable {}
}
