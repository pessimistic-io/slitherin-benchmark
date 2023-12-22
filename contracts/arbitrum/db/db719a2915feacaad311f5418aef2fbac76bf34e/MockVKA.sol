//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "./ERC20.sol";

contract MockVKA is ERC20 {
    constructor() ERC20("MockVKA", "VKA") {
        // mint 100M VKA
        _mint(msg.sender, 100_000_000 * 10**18);
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function mint(uint256 _amount) external {
        _mint(msg.sender, _amount);
    }

    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }

}

