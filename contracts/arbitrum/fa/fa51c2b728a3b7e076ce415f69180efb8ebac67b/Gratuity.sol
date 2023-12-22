//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./console.sol";

contract Gratuity is ReentrancyGuard {
  using Counters for Counters.Counter;
  Counters.Counter private _gratuitiesGiven;

  uint256 totalGratuity;

  address payable public owner;

  constructor() payable {
    owner = payable(msg.sender);
    console.log('LOG: Gratuity contract deployed');
  }

  struct GratuityItem {
    address sender;
    uint256 amount;
    string message;
  }
  GratuityItem[] public gratuityItems;

  event GratuityItemGifted(address sender, uint256 amount, string message);

  function getAllGratuityItems() external view returns (GratuityItem[] memory) {
    return gratuityItems;
  }

  function getTotalGratuity() external view returns (uint256) {
    return totalGratuity;
  }

  function deposit(string calldata _message) public payable {
    require(msg.value > 0, 'You must send ether');
    totalGratuity += msg.value;
    _gratuitiesGiven.increment();
    gratuityItems.push(GratuityItem({sender: msg.sender, amount: msg.value, message: _message}));
    emit GratuityItemGifted(msg.sender, msg.value, _message);
  }

  // Function to withdraw all Ether from this contract.
  function withdraw() public onlyOwner {
    uint256 amount = address(this).balance;

    (bool success, ) = msg.sender.call{value: amount}('');
    require(success, 'Failed to withdraw Ether');
  }

  // Function to transfer Ether from this contract to address from input
  function transfer(address payable _to, uint256 _amount) public onlyOwner nonReentrant {
    // Note that "to" is declared as payable
    (bool success, ) = _to.call{value: _amount}('');
    require(success, 'Failed to send Ether');
  }

  modifier onlyOwner() {
    require(isOwner(), 'caller is not the owner');
    _;
  }

  function isOwner() public view returns (bool) {
    return msg.sender == owner;
  }
}

