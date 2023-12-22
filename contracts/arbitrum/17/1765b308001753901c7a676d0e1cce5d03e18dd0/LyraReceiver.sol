// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./Ownable.sol";

interface ILyraDeposit {
    function initiateDeposit(address beneficiary, uint256 amountQuote) external;
}

interface UniswapRouterV3 {
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}

contract LyraReceiver is Ownable {
    using SafeERC20 for IERC20;
    ILyraDeposit immutable public lyraDepositAddress = ILyraDeposit(0xB619913921356904Bf62abA7271E694FD95AA10D);
    address public immutable depositTokenAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    UniswapRouterV3 immutable public uniswapRouter = UniswapRouterV3(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45) ;

    function swapAndDeposit(
        address token,
        address userAddress,
        uint256 minAmountOut
    ) external {
        uint256 allowance = IERC20(token).allowance(
            msg.sender,
            address(this)
        );
        IERC20(token).approve(address(uniswapRouter), allowance);

        IERC20(token).safeTransferFrom(
            msg.sender,
            address(this),
            allowance);

        try
            uniswapRouter.exactInputSingle(
                UniswapRouterV3.ExactInputSingleParams(
                    token,
                    depositTokenAddress,
                    500,
                    address(this),
                    allowance,
                    minAmountOut,
                    0
                )
            )
        returns (uint256 amountOut) {
            IERC20(depositTokenAddress).approve(
                address(lyraDepositAddress),
                amountOut
            );
            lyraDepositAddress.initiateDeposit(userAddress, amountOut);
        } catch {
            IERC20(token).transfer(userAddress, allowance);
        }
    }

    function deposit(address userAddress) external {
        uint256 allowance = IERC20(depositTokenAddress).allowance(
            msg.sender,
            address(this)
        );


        IERC20(depositTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            allowance);

        IERC20(depositTokenAddress).approve(
            address(lyraDepositAddress),
            allowance
        );
        try
            lyraDepositAddress.initiateDeposit(userAddress, allowance)
        {} catch {
            IERC20(depositTokenAddress).transfer(userAddress, allowance);
        }
    }

    function rescueTokens(address token, address to, uint256 amount) onlyOwner external  {
        IERC20(token).transfer(to, amount);
    }

    function rescueEth(address payable to, uint256 amount) onlyOwner external {
        to.transfer(amount);
    }
}

