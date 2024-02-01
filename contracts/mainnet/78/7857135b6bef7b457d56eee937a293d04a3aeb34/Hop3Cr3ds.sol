//SPDX-License-Identifier: MIT

/*
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
·:··:::··:·····::··::::::·····:::::··:··::··:::··:·····::··::::::·····:::::··:··:
:::::::::::::::::::::::::::::: Hop3 $CR3DS Contract :::::::::::::::::::::::::::::
.:..:::..:.....::..::::::.....:::::..:..::..:::..:.....::..::::::.....:::::..:...
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
·:··:::··:·····::··::::::·····:::::··:··::··:::··:·····::··::::::·····:::::··:··:
:::::::::::: 88        88    ,ad8888ba,    88888888ba    ad888888b,  ::::::::::::
:::::::::::: 88        88   d8"'    `"8b   88      "8b  d8"     "88  ::::::::::::
:::::::::::: 88        88  d8'        `8b  88      ,8P          a8P  ::::::::::::
:::::::::::: 88aaaaaaaa88  88          88  88aaaaaa8P'       aad8"   ::::::::::::
:::::::::::: 88""""""""88  88          88  88""""""'         ""Y8,   ::::::::::::
:::::::::::: 88        88  Y8,        ,8P  88                   "8b  ::::::::::::
:::::::::::: 88        88   Y8a.    .a8P   88           Y8,     a88  ::::::::::::
:::::::::::: 88        88    `"Y8888Y"'    88            "Y888888P'  ::::::::::::
.:..:::..:.....::..::::::.....:::::..:..::..:::..:.....::..::::::.....:::::..:...
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
·:··:::··:·····::··::::::·····:::::··:··::··:::··:·····::··::::::·····:::::··:··:
    8 8                                                                          
 ad88888ba     ,ad8888ba,   88888888ba    ad888888b,  88888888ba,     ad88888ba  
d8" 8 8 "8b   d8"'    `"8b  88      "8b  d8"     "88  88      `"8b   d8"     "8b 
Y8, 8 8      d8'            88      ,8P          a8P  88        `8b  Y8,         
`Y8a8a8a,    88             88aaaaaa8P'       aad8"   88         88  `Y8aaaaa,   
  `"8"8"8b,  88             88""""88'         ""Y8,   88         88    `"""""8b, 
    8 8 `8b  Y8,            88    `8b            "8b  88         8P          `8b 
Y8a 8 8 a8P   Y8a.    .a8P  88     `8b   Y8,     a88  88      .a8P   Y8a     a8P 
 "Y88888P"     `"Y8888Y"'   88      `8b   "Y888888P'  88888888Y"'     "Y88888P"  
    8 8                                                                          
.:..:::..:.....::..::::::.....:::::..:..::..:::..:.....::..::::::.....:::::..:...
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
*/

pragma solidity ^0.8.0;

import "./Ownable.sol";
import {GIGADRIP20} from "./GIGADRIP20.sol";

contract Hop3Cr3ds is Ownable, GIGADRIP20 {
    error NotOwnerOrHop3Contract();

    address public hop3;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _emissionRatePerBlock
    ) GIGADRIP20(_name, _symbol, _decimals, _emissionRatePerBlock) {}

    function startDripping(address addr, uint128 multiplier) external {
        if (msg.sender != hop3 && msg.sender != owner())
            revert NotOwnerOrHop3Contract();
        _startDripping(addr, multiplier);
    }

    function stopDripping(address addr, uint128 multiplier) external {
        if (msg.sender != hop3 && msg.sender != owner())
            revert NotOwnerOrHop3Contract();

        _stopDripping(addr, multiplier);
    }

    function burn(address from, uint256 value) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - value;

        _burn(from, value);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function setHop3Contract(address hop3Address) external onlyOwner {
        hop3 = hop3Address;
    }
}

