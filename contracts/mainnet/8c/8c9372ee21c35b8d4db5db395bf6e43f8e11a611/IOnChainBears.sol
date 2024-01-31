// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC721AQueryable.sol";

interface IOnChainBears is IERC721AQueryable {    
    error NonEOA();
    error InvalidAmount();
    error OverMaxSupply();
    error MaxMinted();
    error NonExistent();
    error Insane();
    error MintInactive();
}
