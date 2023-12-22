//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Bank {
    
   
    mapping(address => uint) _balances;
    uint _totalSupply;
    
    function deposit() public payable {
       
        _balances[msg.sender] += msg.value;
        _totalSupply += msg.value;
        
    }
    
    function withdraw(uint amount) public {
        
       require(amount <= _balances[msg.sender], "not enough money");
        payable(msg.sender).transfer(amount);
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
    }
    
    function checkBalace() public view returns(uint balance) {
        return _balances[msg.sender];
    }
    
    function checkTotalSupply() public view returns(uint totalSupply) {
        return _totalSupply;
    }
}