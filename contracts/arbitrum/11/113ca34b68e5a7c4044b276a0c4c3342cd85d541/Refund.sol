// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Refund is Ownable {
    using SafeMath for uint256;

    IERC20 public refundToken;
    IERC20 public sled;

    address[] addresses;
    mapping(address => uint256) users;
    uint256 price = 0; // usdc per sled

    constructor(address _token, address _sled) {
        refundToken = IERC20(_token);
        sled = IERC20(_sled);
    }

    function setRefundToken(address _token) public onlyOwner {
        refundToken = IERC20(_token);
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    function setSled(address _sled) public onlyOwner {
        sled = IERC20(_sled);
    }

    function moveFunds(address _to) public onlyOwner {
        uint256 balance = IERC20(refundToken).balanceOf(address(this));
        IERC20(refundToken).transfer(_to, balance);
    }

    function isContract(address addr) public view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function calculateSaleQuote(
        uint256 paymentAmount_
    ) public view returns (uint256) {
        return paymentAmount_.mul(price).div(1e18);
    }

    function swapBack(uint256 _amount) public onlyOwner {
        IERC20(sled).transferFrom(msg.sender, address(this), _amount);
        IERC20(refundToken).transfer(msg.sender, calculateSaleQuote(_amount));
    }
}

