// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";

contract MockWETH is ERC20("MockWETH", "WETH"), Ownable {
    uint256 public mintValue = 10 ether;

    function mint() public {
        _mint(msg.sender, mintValue);
    }

    function setMintValue(uint256 _value) public onlyOwner {
        mintValue = _value;
    }
}

