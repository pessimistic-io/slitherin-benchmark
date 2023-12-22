//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "./ERC20.sol";

/// @dev Mock mintable USDC
contract MockVKA is ERC20 {
    constructor() ERC20("MockUSDC", "MUSDC") {}

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function mint(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

    function burnAll() external {
        uint256 _balanceOf = balanceOf(msg.sender);
        require(_balanceOf > 0, "MockUSDC: Nothing to burn");
        _burn(msg.sender, _balanceOf);
    }
}

