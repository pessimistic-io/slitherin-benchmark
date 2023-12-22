// SPDX-License-Identifier: UNLICENSE
pragma solidity ^0.8.21;

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {IFeeConverter} from "./IFeeConverter.sol";
import {ICamelotRouter} from "./ICamelotRouter.sol";

error FundsTransferFailed();

contract FeeConverter is IFeeConverter, Ownable {
    IERC20 public feeToken;
    ICamelotRouter public router;
    address public USDC;

    event WithdrewFees(address indexed receiver, uint256 amount);
    event ConvertFees(uint256 amountIn, uint256 amountOut);

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setFeeToken(address _feeToken) external onlyOwner {
        feeToken = IERC20(_feeToken);
    }

    function setRouter(address _router) external onlyOwner {
        router = ICamelotRouter(_router);
    }

    function setUsdc(address _usdc) external onlyOwner {
        USDC = _usdc;
    }

    function withdrawFees() external onlyOwner {
        address receiver = owner();
        uint256 amount = feeToken.balanceOf(address(this));

        bool sendDmt = feeToken.transfer(receiver, amount);

        if (!sendDmt) {
            revert FundsTransferFailed();
        }

        emit WithdrewFees(receiver, amount);
    }

    function convertFees() external payable returns (bool) {
        // Swap ETH -> USDC -> DMT
        address[] memory path = new address[](3);
        path[0] = router.WETH();
        path[1] = USDC;
        path[2] = address(feeToken);
        uint256 amountOutMin = 0;
        address to = address(this);
        address referrer = address(0);
        uint256 deadline = block.timestamp;

        uint256 balanceBefore = feeToken.balanceOf(address(this));

        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: msg.value
        }(amountOutMin, path, to, referrer, deadline) {
            uint256 balanceAfter = feeToken.balanceOf(address(this));
            emit ConvertFees(msg.value, balanceAfter - balanceBefore);
            return true;
        } catch {
            return false;
        }
    }
}

