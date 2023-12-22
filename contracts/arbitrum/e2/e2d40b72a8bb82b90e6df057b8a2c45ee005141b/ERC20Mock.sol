// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { SolidStateERC20 } from "./SolidStateERC20.sol";

contract ERC20Mock is SolidStateERC20 {
    function _name() internal pure override returns (string memory) {
        return 'Vault';
    }

    function _symbol() internal pure override returns (string memory) {
        return 'VLT';
    }

    function _decimals() internal pure override returns (uint8) {
        return 18;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }
}

