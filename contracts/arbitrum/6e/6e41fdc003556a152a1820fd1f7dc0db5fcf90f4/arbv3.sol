//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
// pragma solidity >=0.5.0 <=0.8.0;

import "./console.sol";

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";

interface IUniswapV2Router {
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

contract ArbV2 is Ownable {
    using SafeMath for uint;

    function swap(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) private {
        IERC20(_tokenIn).approve(router, _amount);
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint deadline = block.timestamp + 300;
        IUniswapV2Router(router).swapExactTokensForTokens(
            _amount,
            1,
            path,
            address(this),
            deadline
        );
    }

    function calculatePriceFromLiquidity(
        address token0,
        address token1,
        uint24 fee,
        address factory
    ) public view returns (uint256) {
        IUniswapV3Pool pool = IUniswapV3Pool(
            IUniswapV3Factory(factory).getPool(token0, token1, fee)
        );

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256 amount0 = FullMath.mulDiv(
            pool.liquidity(),
            FixedPoint96.Q96,
            sqrtPriceX96
        );

        uint256 amount1 = FullMath.mulDiv(
            pool.liquidity(),
            sqrtPriceX96,
            FixedPoint96.Q96
        );

        return (amount1 * 10 ** ERC20(token0).decimals()) / amount0;
    }

    function getAmountOutMin(
        address router,
        address _tokenIn,
        address _tokenOut,
        uint256 _amount
    ) public view returns (uint256) {
        address[] memory path;
        path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        uint256[] memory amountOutMins = IUniswapV2Router(router).getAmountsOut(
            _amount,
            path
        );
        return amountOutMins[path.length - 1];
    }

    function estimateDualDexTrade(
        address _router1,
        address _router2,
        address _token1,
        address _token2,
        uint256 _amount
    ) external view returns (uint256) {
        uint256 amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint256 amtBack2 = getAmountOutMin(
            _router2,
            _token2,
            _token1,
            amtBack1
        );
        return amtBack2;
    }

    function dualDexTrade(
        address _router1,
        address _router2,
        address _token1,
        address _token2,
        uint256 _amount
    ) external onlyOwner {
        uint startBalance = IERC20(_token1).balanceOf(address(this));
        uint token2InitialBalance = IERC20(_token2).balanceOf(address(this));
        swap(_router1, _token1, _token2, _amount);
        uint token2Balance = IERC20(_token2).balanceOf(address(this));
        uint tradeableAmount = token2Balance - token2InitialBalance;
        swap(_router2, _token2, _token1, tradeableAmount);
        uint endBalance = IERC20(_token1).balanceOf(address(this));
        require(endBalance > startBalance, "Trade Reverted, No Profit Made");
    }

    function estimateTriDexTrade(
        address _router1,
        address _router2,
        address _router3,
        address _token1,
        address _token2,
        address _token3,
        uint256 _amount
    ) external view returns (uint256) {
        uint amtBack1 = getAmountOutMin(_router1, _token1, _token2, _amount);
        uint amtBack2 = getAmountOutMin(_router2, _token2, _token3, amtBack1);
        uint amtBack3 = getAmountOutMin(_router3, _token3, _token1, amtBack2);
        return amtBack3;
    }

    function getBalance(
        address _tokenContractAddress
    ) external view returns (uint256) {
        uint balance = IERC20(_tokenContractAddress).balanceOf(address(this));
        return balance;
    }

    function recoverEth() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function recoverTokens(address tokenAddress) external onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    receive() external payable {}
}

