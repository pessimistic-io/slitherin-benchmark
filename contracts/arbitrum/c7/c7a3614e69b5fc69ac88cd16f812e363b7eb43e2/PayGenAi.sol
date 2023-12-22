// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Counters.sol";

contract PayGenAi is Ownable {
    IERC20 public tokenXRAI;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    uint256 pricePayGenAI;
    Counters.Counter private _orderIds;

    event PayGenAI(
        uint256 orderId,
        address sender,
        uint256 amount,
        uint256 timePay
    );

    constructor(address _token) {
        tokenXRAI = IERC20(_token);
    }

    function payGenAi(uint256 _amountToken) external {
        require(_amountToken == pricePayGenAI, "Not enough token XRAI sent.");
        tokenXRAI.safeTransferFrom(msg.sender, address(this), _amountToken);
        _orderIds.increment();
        uint256 _orderId = _orderIds.current();
        emit PayGenAI(_orderId, msg.sender, _amountToken, block.timestamp);
    }

    function setPriceGenAi(uint256 _amount) external onlyOwner {
        pricePayGenAI = _amount;
    }

    function withdraw() external onlyOwner {
        uint256 getAmountToken = tokenXRAI.balanceOf(address(this));
        require(
            tokenXRAI.transfer(_msgSender(), getAmountToken),
            "Failed to transfer tokens"
        );
    }

    function getPricePayTokenGenAI() external view returns (uint256) {
        return pricePayGenAI;
    }

    function getCounterId() external view returns (uint256) {
        return _orderIds.current();
    }

    function getTokenOnContract() external view returns (uint256) {
        return tokenXRAI.balanceOf(address(this));
    }
}

