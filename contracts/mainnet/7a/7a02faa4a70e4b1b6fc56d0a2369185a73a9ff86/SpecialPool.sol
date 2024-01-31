//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./ISpecialPool.sol";
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
contract SpecialPool is ISpecialPool {
  address private factory; 
  constructor() {
    factory = msg.sender;

  }

  function sendToken(address tokenAddress, uint256 amount, address recipient) external override returns (bool){
    require(
      msg.sender == factory,
      "Not factory!"
    );
    IERC20 projectToken = IERC20(tokenAddress);
    if(projectToken.balanceOf(address(this))>=amount){
      projectToken.transfer(recipient, amount);
      return true;
    }else
      return false;
      
  }
  function sendETH(uint256 amount, address recipient) external override returns (bool){
    require(
      msg.sender == factory,
      "Not factory!"
    );
    if(amount>0){
      (bool sent,) = payable(recipient).call{value:amount}("");
      require(sent, "Failed to send Ether");
    }
    return true;
  }


  receive() external payable {
    require(
      msg.sender == factory,
      "Not factory!"
    );
  }
}

