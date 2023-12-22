// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract MockTokenD is ERC20, Ownable {
  using SafeERC20 for IERC20;

  uint8 private _decimals;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _d
  ) ERC20(_name, _symbol) {
    _decimals = _d;
    _mint(msg.sender, 1_000_0000 ether);
  }

   function decimals() public view override returns (uint8) {
      return _decimals;
    }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

