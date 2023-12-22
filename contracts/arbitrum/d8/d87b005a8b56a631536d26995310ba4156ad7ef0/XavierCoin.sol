//SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "./ERC20.sol";

contract XavierCoin is ERC20 {
  
  constructor(uint _totalSupply) ERC20("Xavier", "XAVIER"){
    _mint(msg.sender, _totalSupply);
  }

}



