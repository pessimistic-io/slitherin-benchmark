// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC20.sol";
//import "./IFlashLoanRecipient.sol";
//import "./IBalancerVault.sol";
import "./IUniswapV2Router02.sol";
import "./ICamelotRouter.sol";
import "./ISwapRouter.sol";
import "./IPool.sol";
import "./FlashLoanSimpleReceiverBase.sol";

//import "hardhat/console.sol";

contract FlashLoanArbitrageArbAAVEV3 is FlashLoanSimpleReceiverBase {
    address payable private owner;
    address private sushiV2Router;
    address private sushiV3Router;
    address private zyberRouter;
    address private arbexchangeRouter;
    address private camelotRouter;
    address private uniV3Router;
    address public immutable arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    constructor(
        IPoolAddressesProvider _addressProvider,
        address _sushiV2Router,
        address _arbexchangeRouter,
        address _camelotRouter,
        address _zyberRouter,
        address _uniV3Router,
        address _sushiV3Router
    ) FlashLoanSimpleReceiverBase(_addressProvider) {
        owner = payable(msg.sender);
        sushiV2Router = _sushiV2Router;
        arbexchangeRouter = _arbexchangeRouter;
        camelotRouter = _camelotRouter;
        zyberRouter = _zyberRouter;
        uniV3Router = _uniV3Router;
        sushiV3Router = _sushiV3Router;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only Owner can call this function!");
        _;
    }

    receive() external payable {}

    /*
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
    }*/

    function withdrawOnlyOwner(address token) external payable onlyOwner {
        uint256 amount = 0;
        require(address(token) != address(0), "Invalid token address");
        if (arb == token) {
            amount = address(this).balance;
            require(amount > 0, "Not enough ARB token to WithdrawOnlyOwner");
            payable(owner).transfer(amount);
        } else {
            amount = IERC20(token).balanceOf(address(this));
            require(amount > 0, "Not enough token to WithdrawOnlyOwner");
            IERC20(token).transfer(payable(owner), amount);
        }
    }

    function changeAddresses(
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
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 premium,
        address,
        bytes memory data
    ) external override returns (bool) {
        //console.log("executeOperation...");
        //console.log(IERC20(token).balanceOf(address(this)));
        //console.log(amount);
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
        //console.log("1");
        require(
            IERC20(trade_tokens_dir0[0]).approve(dexA, outputs[0]),
            "Approve for Swapping failed."
        );
        //console.log("2");
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
                    outputs[0],
                    trade_tokens_dir0,
                    address(this),
                    address(0),
                    block.timestamp + 3000
                );
        } else {
            IUniswapV2Router02(dexA).swapExactTokensForTokens(
                outputs[0],
                outputs[1],
                trade_tokens_dir0,
                address(this),
                block.timestamp + 3000
            );
        }
        //console.log("3");
        require(
            IERC20(trade_tokens_dir1[0]).approve(
                dexB,
                IERC20(trade_tokens_dir1[0]).balanceOf(address(this))
            ),
            "Approve for Swapping failed."
        );
        //console.log("4");
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
                    amountOutMinimum: 0, //amount + premium,
                    sqrtPriceLimitX96: 0
                });
            ISwapRouter(dexB).exactInputSingle(params);
        } else if (dexB == camelotRouter) {
            ICamelotRouter(dexB)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    IERC20(trade_tokens_dir1[0]).balanceOf(address(this)),
                    0, //amount + premium,
                    trade_tokens_dir1,
                    address(this),
                    address(0),
                    block.timestamp + 3000
                );
        } else {
            IUniswapV2Router02(dexB).swapExactTokensForTokens(
                IERC20(trade_tokens_dir1[0]).balanceOf(address(this)),
                0, //amount + premium, //outputs[0],
                trade_tokens_dir1,
                address(this),
                block.timestamp + 3000
            );
        }
        //console.log("5");
        //console.log(amount + premium);
        //console.log(IERC20(token).balanceOf(address(this)));
        IERC20(token).approve(address(POOL), amount + premium);
        //IERC20(token).transfer(address(POOL), amount + premium);
        uint256 profit = IERC20(token).balanceOf(address(this)) -
            amount -
            premium;
        //console.log(IERC20(token).balanceOf(address(this)));
        IERC20(token).transfer(owner, profit);
        //console.log(IERC20(token).balanceOf(address(this)));
        return true;
    }

    function flashLoan(
        address token,
        uint256 amount,
        bytes memory userData
    ) external onlyOwner {
        //console.log("starting...");
        //console.log(token);
        //console.log(amount);
        POOL.flashLoanSimple(address(this), token, amount, userData, 0);
    }
}

