
// oooooooooo.             .o8                   ooooooooo.             oooo            .   
// `888'   `Y8b           "888                   `888   `Y88.           `888          .o8   
//  888     888  .oooo.    888oooo.  oooo    ooo  888   .d88'  .ooooo.   888  oooo  .o888oo 
//  888oooo888' `P  )88b   d88' `88b  `88.  .8'   888ooo88P'  d88' `88b  888 .8P'     888   
//  888    `88b  .oP"888   888   888   `88..8'    888`88b.    888ooo888  888888.      888   
//  888    .88P d8(  888   888   888    `888'     888  `88b.  888    .o  888 `88b.    888 . 
// o888bood8P'  `Y888""8o  `Y8bod8P'     .8'     o888o  o888o `Y8bod8P' o888o o888o   "888" 
//                                   .o..P'                                                 
//                                   `Y8P'                                                  
                    

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;                                                                     


import "./ERC20.sol";

contract babyREKT is Context, ERC20 {

	constructor(uint256 _supply) ERC20("Baby REKT", "BREKT") {
		_mint(msg.sender, _supply);
	}

	function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
