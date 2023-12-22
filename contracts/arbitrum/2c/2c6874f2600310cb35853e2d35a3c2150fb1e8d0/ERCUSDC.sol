//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract ERCUSDC is ERC20 {
    constructor() ERC20("ERCUSDC", "ERCUSDC") {
        _mint(address(0xa54eD6cfD0D78d7Ea308Bcc5b9c5E819e8Eebd3D), uint256(500 * 1e6 * 1e6));
        _mint(address(0xEEbf7B8225037A74F75D89D5c4981d9dF33a3251), uint256(500 * 1e6 * 1e6));
    }

	function decimals() public view override returns (uint8) {
		return 6;
	}
}
