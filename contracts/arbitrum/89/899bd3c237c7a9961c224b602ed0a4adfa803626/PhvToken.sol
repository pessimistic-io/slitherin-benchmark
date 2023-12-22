// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";


contract PhvToken is ERC20, Ownable {
  constructor() ERC20("Protohedge Vault", "PHV", 6) {}

  function mint(address to, uint256 amount) onlyOwner external {
      _mint(to, amount);
  }

  function burn(address from, uint256 amount) onlyOwner external {
    _burn(from, amount);
  }
}
