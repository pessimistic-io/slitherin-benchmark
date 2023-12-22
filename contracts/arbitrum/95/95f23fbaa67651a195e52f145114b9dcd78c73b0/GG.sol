// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./console.sol";

interface IChildren {
    function call(address token, bytes calldata data) external payable;
}

contract GG {

    address payable owner;

    address[] public allChildren;

    constructor() {
        owner = payable(msg.sender);
    }
    
    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    function registerChildren(uint32 count) external {
        for(uint32 i = 0; i < count; i++){
            Children children = new Children();
            allChildren.push(address(children));
        }
    }

    function getChildrenCount() public view returns(uint256) {
        return allChildren.length;
    }

    function callChildren(uint32 start, uint32 end, address token, uint256 value, bytes calldata data) external payable onlyOwner {
        for(uint32 i = start; i < end; i++){
            IChildren(allChildren[i]).call{value:value}(token, data);
        }
    }

    function callOneChildren(uint32 index, address token, bytes calldata data) external payable onlyOwner {
        IChildren(allChildren[index]).call{value: msg.value}(token, data);
    }


    function initUSDT(uint32 start, uint32 end, uint256 amount) external onlyOwner {
        for(uint32 i = start; i < end; i++){
            IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9).transfer(allChildren[i], amount);
        }
    }


}


contract Children is IChildren{

    address payable owner;
    
    modifier onlyOwner {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor() {
        owner = payable(msg.sender);
        IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9).approve(0x5da11485b4C990bC6b6FA2a333e25E619c94dB3D, 100000000);
    }

    function call(address token, bytes calldata data) external payable onlyOwner {
        (bool res,) = token.call{value: msg.value }(data);
        if(!res) {
            revert("children call error");
        }
    }
}
