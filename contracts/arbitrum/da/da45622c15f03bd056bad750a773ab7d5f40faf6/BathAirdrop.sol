// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./ERC20.sol";
import "./BathPresale.sol";

contract BathAirdrop is Ownable {
  ERC20 public bathToken = ERC20(0xe5b8C3381C0A2544883CfF9dDaf1e48D9dea9E49);
  BathPresale public presale = BathPresale(0x63E20808FF101F23Ba799533329452F9392087Fd);
  uint public airdropTreshold = 0.01 ether;
  uint public totalAirdrop = 1_000_000 ether;
  uint public totalRaised = 100930967180689540344;
  // 9,907.76198755503294 BATH per ETH
  uint public airdropAmountPerEth = (totalAirdrop * 1 ether) / totalRaised;

  mapping(address => bool) public alreadyClaimed;

  function isOpen() public view returns (bool) {
    return bathToken.balanceOf(address(this)) > 0;
  }

  function isEligible(address _address) public view returns (bool) {
    return presale.balanceOf(_address) >= airdropTreshold;
  }

  function claimableAmount(address _address) public view returns (uint) {
    if (alreadyClaimed[_address] || !isEligible(_address)) {
      return 0;
    }

    uint raisedByAddress = presale.balanceOf(_address);
    return (raisedByAddress * airdropAmountPerEth) / 1 ether;
  }

  function claim() public {
    require(isOpen(), "Not open");
    require(!alreadyClaimed[msg.sender], "Already claimed");
    require(isEligible(msg.sender), "Not eligible");

    uint airdropAmount = claimableAmount(msg.sender);
    alreadyClaimed[msg.sender] = true;
    bathToken.transfer(msg.sender, airdropAmount);
  }

  // admin

  function setAirdropTreshold(uint _treshold) public onlyOwner {
    airdropTreshold = _treshold;
  }

  function setAirdropAmountPerEth(uint _amount) public onlyOwner {
    airdropAmountPerEth = _amount;
  }

  function withdrawToken(address _token, uint _amount) public onlyOwner {
    ERC20(_token).transfer(msg.sender, _amount);
  }
}

