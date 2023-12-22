// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

// Every other hour we run moveFunds() on this contract to move funds from this to the secondary contract
contract AmxTosserMain is Ownable {
  ERC20 public amx;
  address public amxTosserSecondary;
  address public staker;

  constructor(address _amx) {
    amx = ERC20(_amx);
  }

  function setAmxTosserSecondary(address _amxTosserSecondary) public onlyOwner {
    amxTosserSecondary = _amxTosserSecondary;
  }

  function setStaker(address _staker) public onlyOwner {
    staker = _staker;
  }

  function moveFunds() public onlyOwner {
    amx.transfer(amxTosserSecondary, amx.balanceOf(address(this)));
  }

  function moveFundsToStaker() public onlyOwner {
    amx.transfer(staker, amx.balanceOf(address(this)));
  }

  // allow withdrawing airdropped tokens
  function withdrawAny(address _token) public onlyOwner {
    ERC20 token = ERC20(_token);
    token.transfer(msg.sender, token.balanceOf(address(this)));
  }
}

