// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.11;

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeMath.sol";
import "./WhitelistData.sol";

contract BathPresale is Ownable {
  struct Account {
    uint balance;
    uint tokenClaimedAt;
    uint refundedAt;
  }

  mapping (address => Account) public accounts;

  bool public refundOpen;
  bool public claimOpen;

  uint public privateRaiseOpenAt;
  uint public publicRaiseOpenAt;
  uint public raiseCloseAt;

  uint public raiseTarget;
  uint public wlTotalRaised;
  uint public totalRaised;
  ERC20 public token;
  uint public tokenPrice = 0.00001 ether;
  address public wlDataAddress;
  uint public maxPerWallet = 2 ether;

  modifier onlyWhitelist() {
    require(isValidWhitelist(msg.sender), "Not whitelisted");
    _;
  }

  modifier depositRequirements() {
    require(totalRaised < raiseTarget, "Target reached");
    require(msg.value >= 0.01 ether, "Minimum 0.01 ETH");
    _;
  }

  constructor(uint _target, uint _privateRaiseOpenAt, address _wlDataAddress) {
    raiseTarget = _target;
    privateRaiseOpenAt = _privateRaiseOpenAt;
    publicRaiseOpenAt = privateRaiseOpenAt + 2 hours;
    raiseCloseAt = privateRaiseOpenAt + 1 days;

    wlDataAddress = _wlDataAddress;
  }

  function balanceOf(address _address) public view returns (uint) {
    return accounts[_address].balance;
  }

  function depositPrivate() public payable depositRequirements onlyWhitelist {
    require(privateRaiseOpenAt <= block.timestamp && raiseCloseAt > block.timestamp , "Sale is not open");
    wlTotalRaised += msg.value;
    _deposit();
  }

  function depositPublic() public payable depositRequirements {
    require(publicRaiseOpenAt <= block.timestamp && raiseCloseAt > block.timestamp , "Sale is not open");
    _deposit();
  }

  function _deposit() private {
    if(msg.sender != owner()){
      require(accounts[msg.sender].balance + msg.value <= maxPerWallet, "Over max per address");
    }

    accounts[msg.sender].balance += msg.value;
    totalRaised += msg.value;
  }

  function isValidWhitelist(address _address) public view returns (bool) {
    return WhitelistData(wlDataAddress).isWhitelisted(_address);
  }

  function getTokenAmount(uint _ethAmount) public view returns (uint) {
    // balance * 1 ether / tokenPrice
    return SafeMath.div(SafeMath.mul(_ethAmount, 1 ether), tokenPrice);
  }

  function claim() public {
    require(claimOpen, "Claim is closed");
    require(accounts[msg.sender].tokenClaimedAt == 0, "Already claimed");

    uint tokenAmount = getTokenAmount(accounts[msg.sender].balance);
    require(tokenAmount > 0, "No tokens to claim");

    accounts[msg.sender].tokenClaimedAt = block.timestamp;
    token.transfer(msg.sender, tokenAmount);
  }

  function refund() public {
    require(refundOpen, "Refund is not open");
    require(accounts[msg.sender].balance > 0, "No balance");

    uint amount = accounts[msg.sender].balance;
    accounts[msg.sender].refundedAt = block.timestamp;
    payable(msg.sender).transfer(amount);
  }

  // Admin functions

  function toggleRefund(bool _open) public onlyOwner {
    refundOpen = _open;
  }

  function toggleClaim(bool _open) public onlyOwner {
    claimOpen = _open;
  }

  function setPrivateRaiseOpenAt(uint _timestamp) public onlyOwner {
    privateRaiseOpenAt = _timestamp;
    publicRaiseOpenAt = privateRaiseOpenAt + 2 hours;
    raiseCloseAt = privateRaiseOpenAt + 1 days;
  }

  function setRaiseTarget(uint _target) public onlyOwner {
    raiseTarget = _target;
  }

  function setToken(address _address) public onlyOwner {
    token = ERC20(_address);
  }

  function setTokenPrice(uint _price) public onlyOwner {
    tokenPrice = _price;
  }

  function setWhitelistDataAddress(address _address) public onlyOwner {
    wlDataAddress = _address;
  }

  function setMaxPerWallet(uint _max) public onlyOwner {
    maxPerWallet = _max;
  }

  function withdraw() public onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
  }

  function withdrawToken(address _token) public onlyOwner {
    ERC20 t = ERC20(_token);
    t.transfer(msg.sender, t.balanceOf(address(this)));
  }
}

