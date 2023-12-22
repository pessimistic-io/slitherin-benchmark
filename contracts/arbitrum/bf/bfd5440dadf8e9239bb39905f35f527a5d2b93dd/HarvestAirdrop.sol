// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./ERC20.sol";
import "./HarvestPresale.sol";

contract HarvestAirdrop is Ownable {
  ERC20 public token;
  HarvestPresale public presale;
  uint public airdropTreshold = 0.01 ether;
  uint public totalAirdrop = 50_000 ether;
  uint public totalRaised = 100 ether;
  // X HRVST per ETH
  uint public airdropAmountPerEth = (totalAirdrop * 1 ether) / totalRaised;

  bool public isOpen;

  mapping(address => bool) public alreadyClaimed;

  constructor(address _token, address _presale) {
    token = ERC20(_token);
    presale = HarvestPresale(_presale);
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
    require(isOpen, "Not open");
    require(!alreadyClaimed[msg.sender], "Already claimed");
    require(isEligible(msg.sender), "Not eligible");

    uint airdropAmount = claimableAmount(msg.sender);
    alreadyClaimed[msg.sender] = true;
    token.transfer(msg.sender, airdropAmount);
  }

  // admin

  function updateTotalRaised(uint _raised) public onlyOwner {
    totalRaised = _raised;
    airdropAmountPerEth = (totalAirdrop * 1 ether) / totalRaised;
  }

  function toggleOpen() public onlyOwner {
    isOpen = !isOpen;
  }

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

