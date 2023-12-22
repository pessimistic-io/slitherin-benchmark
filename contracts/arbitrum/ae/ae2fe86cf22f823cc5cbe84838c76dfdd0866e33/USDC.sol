// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function bulkMint(address[] calldata to, uint256 amount) external {
        for(uint256 i = 0; i < to.length; i++) {
            _mint(to[i], amount);
        }
    }

    // function decimals() public view virtual override returns (uint8) {
    //     return 6;
    // }
}
