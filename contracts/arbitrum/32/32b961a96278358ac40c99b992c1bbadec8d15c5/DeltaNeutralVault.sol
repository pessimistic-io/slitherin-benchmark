// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";


// Stores the assets
contract DeltaNeutralVault is Ownable {
  ERC20 private usdcToken;
  
  constructor(address _usdcAddress) {
    usdcToken = ERC20(_usdcAddress);
  }

  function approveUsdc(address spender, uint256 amount) external onlyOwner {
    usdcToken.approve(spender, amount);
  }

  function transferToken(address tokenAddress, address recipient, uint256 amount) external onlyOwner {
    ERC20(tokenAddress).transfer(recipient, amount);
  }
}

