// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.18;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./ERC20.sol";

interface ICamelotPair {
    
    function token0() external view returns(address);
    function token1() external view returns(address);

    function getReserves() external view returns( uint112, uint112,  uint16, uint16 );
}


contract MomoJackpotTool is Ownable {
    using SafeMath for uint256;
    ICamelotPair public anchorPair;
    ICamelotPair public targetPair;

    address public uToken;
    address public anchorToken;
    address public targetToken;

    uint8 public uDecimals;
    uint8 public anchorDecimals;
    uint8 public targetDecimals;
    
    constructor(address anchorpair_, address uToken_, address anchorToken_){
        
        anchorPair = ICamelotPair(anchorpair_);
        uToken = uToken_;
        anchorToken = anchorToken_;

        uDecimals = IERC20Metadata(uToken).decimals();
        anchorDecimals = IERC20Metadata(anchorToken).decimals();
    }

    function getAnchorPrice() public view returns(uint256) {
        
        (uint112 res0, uint112 res1, , ) = anchorPair.getReserves();
        (uint256 uRes, uint256 anchorRes) = anchorPair.token0() == uToken ? (res0, res1) : (res1, res0);

        uint256 anchorPrice = uRes.mul(10**anchorDecimals).div(anchorRes).div(10**uDecimals);
        return anchorPrice;
    }

    function getAnchorPriceMul12() public view returns(uint256) {
        return getAnchorPrice().mul(1e12);
    }

    function getCurrentUsdPrice(uint256 amount) external view returns(uint256 price) {

        // to save float
        uint256 anchorPrice12 = getAnchorPriceMul12();
        uint256 _amount = amount.div(10**targetDecimals);

        (uint112 res0, uint112 res1, , ) = targetPair.getReserves();
        (uint256 targetRes, uint256 anchorRes) = targetPair.token0() == targetToken ? (res0, res1) : (res1, res0);

        uint256 tokenPrice12 = anchorRes.mul(anchorPrice12).mul(10**targetDecimals).div(targetRes).div(10**anchorDecimals);

        return _amount.mul(tokenPrice12).div(1e12);
    }

    function setPairs(address anchorPair_, address targetPair_, address usd_, address anchor_, address target_) external onlyOwner {
        require(anchorPair_ != address(0), "anchorPair_ is the zero address");
        require(targetPair_ != address(0), "targetPair_ is the zero address");
        require(usd_ != address(0), "usd_ is the zero address");
        require(anchor_ != address(0), "anchor_ is the zero address");
        require(target_ != address(0), "target_ is the zero address");

        anchorPair = ICamelotPair(anchorPair_);
        targetPair = ICamelotPair(targetPair_);

        uToken = usd_;
        anchorToken = anchor_;
        targetToken = target_;

        uDecimals = IERC20Metadata(uToken).decimals();
        anchorDecimals = IERC20Metadata(anchorToken).decimals();
        targetDecimals = IERC20Metadata(targetToken).decimals();
    }

    function setAnchorPair(address anchorPair_, address usd_, address anchor_) external onlyOwner {

        anchorPair = ICamelotPair(anchorPair_);
        uToken = usd_;
        anchorToken = anchor_;

        uDecimals = IERC20Metadata(uToken).decimals();
        anchorDecimals = IERC20Metadata(anchorToken).decimals();
    }

    function setTarget(address targetPair_, address target_) external onlyOwner {

        targetPair = ICamelotPair(targetPair_);

        targetToken = target_;
        targetDecimals = IERC20Metadata(targetToken).decimals();
    }

    receive() external payable {}
}

