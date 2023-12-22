// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./SafeMath.sol";
import "./IERC20.sol";

contract CTSTracker {
    using SafeMath for uint256;

    uint256 private constant DIVISION_FACTOR = 10000;
    address owner;
    address public scrollPad;
    address public cattiePreSale;
    address public catitePublicSale;
    uint256 public preSaleRate;
    uint256 public publicSaleRate;
    address  public CTS;
    mapping(address => bool) public isClaimedScrollPad;
    mapping(address => bool) public isClaimedCattiePreSale;
    mapping(address => bool) public isClaimedCattiePublicSale;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(){
        owner = msg.sender;
        cattiePreSale = address(0xD1d6267A6884279C082Ad566d8BF21cd9812Dc6C);
        catitePublicSale = address(0xc03861eAD8272783Fd84db0dFc1F21d5D34f9Fe6);
        CTS = address(0x2a13808DD6a203aF83A35d3a43167728589b6E4d);
        preSaleRate = 7500;
        publicSaleRate = 3000;
    }

    function claim(uint256 padType) public{
        address user = msg.sender;
        uint256 claimAmount = 0;
        if(padType == 0){
            require(!isClaimedCattiePreSale[user], "Already claimed");
            claimAmount = _getClaimAmount(cattiePreSale, user, preSaleRate);
            isClaimedCattiePreSale[user] = true;
        } else if(padType == 1){
            require(!isClaimedCattiePublicSale[user], "Already claimed");
            claimAmount = _getClaimAmount(catitePublicSale, user, publicSaleRate);
            isClaimedCattiePublicSale[user] = true;
        } else if(padType == 2){
            require(!isClaimedScrollPad[user], "Already claimed");
            claimAmount = _getClaimAmount(scrollPad, user, publicSaleRate);
            isClaimedScrollPad[user] = true;
        }
        IERC20(CTS).transfer(user, claimAmount);
    }

    function _getClaimAmount(address padAddress, address user, uint256 rate) private returns(uint256){
        bytes memory payload = abi.encodeWithSignature("boughtAmount(address)", user);
        (bool success, bytes memory result) = padAddress.call(payload);

        if (success) {
            uint256 boughtAmount = abi.decode(result, (uint256));
            return boughtAmount.mul(rate).div(DIVISION_FACTOR);
        } else {
            revert("Failed to fetch data from pad");
        }
    }

    function setScrollPad(address _scrollPad) external onlyOwner {
        scrollPad = _scrollPad;
    }

    function setCattiePreSale(address _cattiePreSale) external onlyOwner {
        cattiePreSale = _cattiePreSale;
    }

    function setCatitePublicSale(address _catitePublicSale) external onlyOwner {
        catitePublicSale = _catitePublicSale;
    }

    function setPreSaleRate(uint256 _preSaleRate) external onlyOwner {
        preSaleRate = _preSaleRate;
    }

    function setPublicSaleRate(uint256 _publicSaleRate) external onlyOwner {
        publicSaleRate = _publicSaleRate;
    }

    function setCTS(address _CTS) external onlyOwner {
        CTS = _CTS;
    }

    function withdraw(address payable recipient) public onlyOwner {
        recipient.transfer(address(this).balance);
        uint256 cts = IERC20(CTS).balanceOf(address(this));
        IERC20(CTS).transfer(recipient, cts);
    }
}

