

// ██████╗ ██╗   ██╗██╗     ██╗     ██████╗ ███████╗ █████╗ ██████╗      █████╗ ██╗
// ██╔══██╗██║   ██║██║     ██║     ██╔══██╗██╔════╝██╔══██╗██╔══██╗    ██╔══██╗██║
// ██████╔╝██║   ██║██║     ██║     ██████╔╝█████╗  ███████║██████╔╝    ███████║██║
// ██╔══██╗██║   ██║██║     ██║     ██╔══██╗██╔══╝  ██╔══██║██╔══██╗    ██╔══██║██║
// ██████╔╝╚██████╔╝███████╗███████╗██████╔╝███████╗██║  ██║██║  ██║    ██║  ██║██║
// ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝
                                                                                



// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;                                                                     


import "./ERC20.sol";

contract bullBearAI is Context, ERC20 {

	constructor(uint256 _supply) ERC20("BullBear AI", "AIBB") {
		_mint(msg.sender, _supply);
	}

	function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
