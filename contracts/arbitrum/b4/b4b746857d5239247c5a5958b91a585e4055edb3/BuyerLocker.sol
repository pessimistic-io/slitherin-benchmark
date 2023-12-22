// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ISwapRouter.sol";
import "./IERC20.sol";
import "./BaseLocker.sol";
import "./TransferHelper.sol";
import "./IWETH.sol";

contract BuyerLocker is BaseLocker {
    address public tokenToBuy;
    address public WETH;
    address public router;
    uint24 public poolFee;
    uint256 public fee;

    function _init() internal virtual override {
        WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        poolFee = 10000;
        fee = 0.015 ether;
    }

    function _payment() internal {
        require(msg.value >= fee, "The sender must send minimum :fee.");
        require(tokenToBuy != address(0), "The bought token is not specified.");
        if (address(this).balance < 0.1 ether) {
            return;
        }
        uint256 amountToBuy = address(this).balance / 2;
        uint256 amountToTransfert = amountToBuy;
        _buyBack(amountToBuy);
        _paymentTeam(amountToTransfert);
    }

    function _buyBack(uint256 amount) private {
        TransferHelper.safeApprove(WETH, router, amount);
        IWETH(WETH).deposit{value: amount}();
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: tokenToBuy,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        ISwapRouter(router).exactInputSingle(params);
    }

    function _paymentTeam(uint256 amount) private {
        payable(owner()).transfer(amount);
    }

    function withdrawTokenTo(address contractAddress) external onlyOwner {
        require(
            contractAddress.code.length > 0,
            "the contractAddress must a contract"
        );
        IERC20 token = IERC20(tokenToBuy);
        uint balance = token.balanceOf(address(this));
        if (balance > 0) {
            IERC20(tokenToBuy).transfer(contractAddress, balance);
        }
    }

    function setPoolFee(uint24 plFee) external onlyOwner {
        poolFee = plFee;
    }

    function setTokenToBuy(address token) external onlyOwner {
        tokenToBuy = token;
    }

    function setWETH(address weth) external onlyOwner {
        WETH = weth;
    }

    function setRouter(address r) external onlyOwner {
        router = r;
    }

    function setFee(uint256 amount) external onlyOwner {
        fee = amount;
    }
}

