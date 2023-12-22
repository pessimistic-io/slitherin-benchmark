// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./IFlashLoanRecipient.sol";
import "./IBalancerVault.sol";
import "./IUniswapV2Router02.sol";
import "./ICamelotRouter.sol";
import "./ISwapRouter.sol";

contract FlashLoanArbitrageArb {
    address payable private owner;
    address private vault;
    address private sushiV2Router;
    address private sushiV3Router;
    address private zyberRouter;
    address private arbexchangeRouter;
    address private camelotRouter;
    address private uniV3Router;
    address public immutable arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    constructor(
        address _vault,
        address _sushiV2Router,
        address _arbexchangeRouter,
        address _camelotRouter,
        address _zyberRouter,
        address _uniV3Router,
        address _sushiV3Router
    ) {
        owner = payable(msg.sender);
        sushiV2Router = _sushiV2Router;
        arbexchangeRouter = _arbexchangeRouter;
        camelotRouter = _camelotRouter;
        zyberRouter = _zyberRouter;
        uniV3Router = _uniV3Router;
        sushiV3Router = _sushiV3Router;
        vault = _vault;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only Owner can call this function!");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only Vault can call this function!");
        _;
    }

    receive() external payable {}

    function withdraw(IERC20 token) private {
        //If contract needs to be funded, then compare here, that everytime there is enough arb here
        uint256 amount = 0;
        require(address(token) != address(0), "Invalid token address");
        if (arb == address(token)) {
            amount = address(this).balance;
            require(amount > 0, "Not enough ARB token to Withdraw");
            owner.transfer(amount);
        } else {
            amount = token.balanceOf(address(this));
            require(amount > 0, "Not enough token to Withdraw");
            token.transfer(owner, amount);
        }
    }

    function withdrawOnlyOwner(address token) external payable onlyOwner {
        uint256 amount = 0;
        require(address(token) != address(0), "Invalid token address");
        if (arb == token) {
            amount = address(this).balance;
            require(amount > 0, "Not enough ARB token to WithdrawOnlyOwner");
            payable(msg.sender).transfer(amount);
        } else {
            IERC20 token_transfer = IERC20(token);
            amount = token_transfer.balanceOf(address(this));
            require(amount > 0, "Not enough token to WithdrawOnlyOwner");
            token_transfer.transfer(payable(msg.sender), amount);
        }
    }

    function changeAddresses(
        address _vault,
        address _sushiV2Router,
        address _arbexchangeRouter,
        address _camelotRouter,
        address _zyberRouter,
        address _uniV3Router,
        address _sushiV3Router
    ) external onlyOwner {
        sushiV2Router = _sushiV2Router;
        arbexchangeRouter = _arbexchangeRouter;
        camelotRouter = _camelotRouter;
        zyberRouter = _zyberRouter;
        uniV3Router = _uniV3Router;
        sushiV3Router = _sushiV3Router;
        vault = _vault;
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory data
    ) external onlyVault {
        address dexA;
        address dexB;
        address[] memory trade_tokens_dir0;
        address[] memory trade_tokens_dir1;
        uint256[] memory outputs;
        uint24[] memory poolFee;
        (
            dexA,
            dexB,
            trade_tokens_dir0,
            trade_tokens_dir1,
            outputs,
            poolFee
        ) = abi.decode(
            data,
            (address, address, address[], address[], uint256[], uint24[])
        );
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i] + feeAmounts[i];
            require(
                IERC20(trade_tokens_dir0[0]).approve(dexA, outputs[0]),
                "Approve for Swapping failed."
            );

            if (dexA == uniV3Router || dexA == sushiV3Router) {
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: address(trade_tokens_dir0[0]),
                        tokenOut: address(trade_tokens_dir0[1]),
                        fee: poolFee[0],
                        recipient: address(this),
                        deadline: block.timestamp + 3000,
                        amountIn: outputs[0],
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });
                ISwapRouter(dexA).exactInputSingle(params);
            } else if (dexA == camelotRouter) {
                ICamelotRouter(dexA)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        outputs[0],
                        0, //outputs[0],
                        trade_tokens_dir0,
                        address(this),
                        address(0),
                        block.timestamp + 3000
                    );
            } else {
                IUniswapV2Router02(dexA).swapExactTokensForTokens(
                    outputs[0],
                    0, //outputs[1],
                    trade_tokens_dir0,
                    address(this),
                    block.timestamp + 3000
                );
            }
            require(
                IERC20(trade_tokens_dir1[0]).approve(
                    dexB,
                    IERC20(trade_tokens_dir1[0]).balanceOf(address(this))
                ),
                "Approve for Swapping failed."
            );
            if (dexB == uniV3Router || dexB == sushiV3Router) {
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: address(trade_tokens_dir1[0]),
                        tokenOut: address(trade_tokens_dir1[1]),
                        fee: poolFee[1],
                        recipient: address(this),
                        deadline: block.timestamp + 3000,
                        amountIn: IERC20(trade_tokens_dir1[0]).balanceOf(
                            address(this)
                        ),
                        amountOutMinimum: 0, //outputs[0],
                        sqrtPriceLimitX96: 0
                    });
                ISwapRouter(dexB).exactInputSingle(params);
            } else if (dexB == camelotRouter) {
                ICamelotRouter(dexB)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        IERC20(trade_tokens_dir1[0]).balanceOf(address(this)),
                        0, //outputs[0],
                        trade_tokens_dir1,
                        address(this),
                        address(0),
                        block.timestamp + 3000
                    );
            } else {
                IUniswapV2Router02(dexB).swapExactTokensForTokens(
                    IERC20(trade_tokens_dir1[0]).balanceOf(address(this)),
                    0, //outputs[0],
                    trade_tokens_dir1,
                    address(this),
                    block.timestamp + 3000
                );
            }
            token.transfer(vault, amount);
            withdraw(tokens[i]);
        }
    }

    function flashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external onlyOwner {
        IBalancerVault(vault).flashLoan(
            IFlashLoanRecipient(address(this)),
            tokens,
            amounts,
            userData
        );
    }
}

