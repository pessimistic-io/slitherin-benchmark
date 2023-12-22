// SPDX-License-Identifier: MIT
/*
    * @title ERC4626Metadata
    * @dev Decendant of ERC4626 that takes in an IERC20Metadata instead of an IERC20. 
    * This allows for the name and symbol to be used contract logic.
*/

pragma solidity =0.8.15;
import "./ERC4626.sol";
import "./extensions_IERC20Metadata.sol";

abstract contract ERC4626Metadata is ERC4626 {

    constructor(IERC20Metadata asset_)
    ERC4626(
        asset_
    ) {} 

}
