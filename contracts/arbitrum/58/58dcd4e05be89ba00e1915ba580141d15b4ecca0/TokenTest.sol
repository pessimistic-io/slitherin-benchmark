// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IbToken.sol";

contract DogeLeverage is ERC20, Ownable {

  address DEAD = 0x000000000000000000000000000000000000dEaD;
  address ZERO = 0x0000000000000000000000000000000000000000;

  address tradingFundAddress;
  IbToken bToken;

  mapping (address => bool) isFundExempt;
  mapping (address => bool) public pairs;

  uint8 public tradingFund = 10;

  constructor() ERC20("TokenTest", "TT") {
    isFundExempt[DEAD] = true;
    isFundExempt[ZERO] = true;
    _mint(msg.sender, 1_000_000 * 10 ** 18);
  }

  function transfer(address to, uint256 amount) public virtual override returns (bool) {
    address from = _msgSender();
    uint _amount = amount;

    if(pairs[from] && address(bToken) != address(0)){
      _amount = amount / tradingFund * 100;
      bToken.mint(to, amount - _amount);
    }
    _transfer(from, to, _amount);
    return true;
  }
  
  function setTradingFund(uint8 _tradingFund) external onlyOwner {
      tradingFund = _tradingFund;
  }

  function setTradingFundAddress(address addr) external onlyOwner {
    tradingFundAddress = addr;
  }

  function addNewPair(address newPair)external onlyOwner{
    pairs[newPair] = true;
    isFundExempt[newPair] = true;
  }

  function removePair(address pairToRemove)external onlyOwner{
    pairs[pairToRemove] = false;
    isFundExempt[pairToRemove] = false;
  }

  function setBtoken(address addr) external onlyOwner {
    bToken = IbToken(addr);
  }

  function withdraw(uint amount) public onlyOwner {
    require(address(this).balance >= amount);
    payable(tradingFundAddress).transfer(amount);
  }

  receive() external payable { }
}
