// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IBeets.sol";
import "./ISwapsUni.sol";
import "./IAsset.sol";

contract SelectSwapRoute is Ownable {
    using SafeERC20 for IERC20;

    address immutable swapsUni;
    address immutable swapsBeets;
    address private nodes;

     modifier onlyAllowed() {
        require(msg.sender == owner() || msg.sender == nodes, 'You must be the owner.');
        _;
    }
    constructor(address swapsUni_, address swapsBeets_) {
        swapsUni = swapsUni_;
        swapsBeets = swapsBeets_;
    }

    function setNodes(address nodes_) public onlyAllowed {
        nodes = nodes_;
    }

    function swapTokens(IAsset[] memory tokens_, uint256 amount_, uint256 amountOutMin_, BatchSwapStep[] memory batchSwapStep_, uint8 provider_) public onlyAllowed returns(uint256 amountOut) {
        address tokenIn_ = address(tokens_[0]);
        address tokenOut_ = address(tokens_[tokens_.length - 1]);
        IERC20(tokenIn_).safeTransferFrom(msg.sender, address(this), amount_);

        if (provider_ == 0) {
            _approve(tokenIn_, address(swapsUni), amount_);
            amountOut = ISwapsUni(swapsUni).swapTokens(tokenIn_, amount_, tokenOut_, amountOutMin_);
        } else {
            _approve(tokenIn_, address(swapsBeets), amount_);
            batchSwapStep_[0].amount = amount_;
            amountOut = IBeets(swapsBeets).swapTokens(tokens_, batchSwapStep_);
        }
        IERC20(tokenOut_).safeTransfer(msg.sender, amountOut);
    }

    /**
     * @notice Approve of a token
     * @param token_ Address of the token wanted to be approved
     * @param spender_ Address that is wanted to be approved to spend the token
     * @param amount_ Amount of the token that is wanted to be approved.
     */
    function _approve(address token_, address spender_, uint256 amount_) internal {
        IERC20(token_).safeApprove(spender_, 0);
        IERC20(token_).safeApprove(spender_, amount_);
    }

}
