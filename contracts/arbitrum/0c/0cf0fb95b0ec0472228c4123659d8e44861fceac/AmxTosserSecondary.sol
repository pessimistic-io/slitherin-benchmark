// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "./ERC20.sol";
import "./Ownable.sol";

// Every other hour we run moveFunds() on this contract to move funds from this to the main contract
contract AmxTosserSecondary is Ownable {
  ERC20 public amx;
  address public amxTosserMain;

  constructor(address _amx) {
    amx = ERC20(_amx);
  }

  function setAmxTosserMain(address _amxTosserMain) public onlyOwner {
    amxTosserMain = _amxTosserMain;
  }

  function moveFunds() public onlyOwner {
    amx.transfer(amxTosserMain, amx.balanceOf(address(this)));
  }

  // allow withdrawing airdropped tokens
  function withdrawAny(address _token) public onlyOwner {
    ERC20 token = ERC20(_token);
    token.transfer(msg.sender, token.balanceOf(address(this)));
  }
}

