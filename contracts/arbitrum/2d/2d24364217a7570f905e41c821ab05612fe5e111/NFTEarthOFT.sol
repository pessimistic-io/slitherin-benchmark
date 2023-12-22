// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//     _   ____________________           __  __    ____  ____________
//    / | / / ____/_  __/ ____/___ ______/ /_/ /_  / __ \/ ____/_  __/
//   /  |/ / /_    / / / __/ / __ `/ ___/ __/ __ \/ / / / /_    / /   
//  / /|  / __/   / / / /___/ /_/ / /  / /_/ / / / /_/ / __/   / /    
// /_/ |_/_/     /_/ /_____/\__,_/_/   \__/_/ /_/\____/_/     /_/     

import "./OFT.sol";

// @title An OmnichainFungibleToken built with the LayerZero OFT standard

contract NFTEarthOFT is OFT {
   constructor(string memory _name, string memory _symbol, address _layerZeroEndpoint) OFT(_name, _symbol, _layerZeroEndpoint) {
        // mint 100M to deployer
        _mint(_msgSender(), 100_000_000 * 10**18);
    }
}
