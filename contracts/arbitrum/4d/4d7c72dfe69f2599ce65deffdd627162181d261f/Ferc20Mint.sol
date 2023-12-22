// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./console.sol";

interface IFairToken is IERC20 {
    function mint(address receiver) external payable ;
    function getMintFee(address addr) external view returns(uint256 mintedTimes, uint256 nextMintFee);
}

interface IChildren {
    function mint(address token, address receiver, bool isApprove) external payable;
}

contract FansMint {

    address payable owner;

    address[] public allChildren;

    constructor() {
        owner = payable(msg.sender);
    }
    
    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    function registerMinter(uint32 count) external {
        for(uint32 i = 0; i < count; i++){
            Children children = new Children();
            allChildren.push(address(children));
        }
    }

    function getMinterCount() public view returns(uint256) {
        return allChildren.length;
    }

    function mint(uint32 count, address token, address receiver, uint256 nextMintFee, bool isApprove) external payable onlyOwner {
        require(count <= getMinterCount(), "count error");
        for(uint32 i = 0; i < count; i++){
            IChildren(allChildren[i]).mint{value:nextMintFee}(token, receiver, isApprove);
        }
        
        if(!isApprove) {
            IFairToken(token).transfer(receiver, IFairToken(token).balanceOf(address(this)));
        }
    }

    function transferAll(address token, address receiver) external onlyOwner {
        for(uint256 i = 0; i < allChildren.length; i++){
            _transferOne(token, i, receiver);
        }
    }

    function transferOne(address token, uint256 index, address receiver) external onlyOwner {
        _transferOne(token, index, receiver);
    }

    function _transferOne(address token, uint256 index, address receiver) internal onlyOwner {
        IFairToken(token).transferFrom(allChildren[index], receiver, IFairToken(token).balanceOf(allChildren[index]));
    }
}


contract Children {
    function mint(address token, address receiver, bool isApprove) external payable {
        console.log("mint fee", msg.value);
        IFairToken(token).mint{value: msg.value }(address(this));
        if(isApprove) {
            IFairToken(token).approve(msg.sender, type(uint256).max);
        } else {
            IFairToken(token).transfer(receiver, IFairToken(token).balanceOf(address(this)));
        }
    }
}
