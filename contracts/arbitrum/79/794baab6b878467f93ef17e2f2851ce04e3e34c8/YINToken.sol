// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "./Ownable.sol";
import "./ERC20.sol";
import "./SafeMath.sol";

contract Yin is ERC20, Ownable {
    using SafeMath for uint256;

    uint256 public maxTotalSupply;

    // maximumTotalSupply = 100000000000000000000000000
    constructor(uint256 _maxTotalSupply) ERC20("YIN Finance", "YIN") {
        maxTotalSupply = _maxTotalSupply;
    }

    function mint(address account, uint256 amount) external onlyOwner {
        require(amount > 0, "ZERO");
        require(amount.add(totalSupply()) <= maxTotalSupply, "maximum minted");
        _mint(account, amount);
    }
}

