// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./ONFT721.sol";

import {IDuelPepesWhitelist} from "./IDuelPepesWhitelist.sol";
import {IDuelPepes} from "./IDuelPepes.sol";

/// @title Interface of the UniversalONFT standard
contract UniversalONFT721 is ONFT721 {
    address public trustedMinter;
    uint public nextMintId;
    uint public publicMints;
    uint public maxPublicMints;

    /// @notice Constructor for the UniversalONFT
    /// @param _maxPublicMints the max number of public sale mints on this chain
    /// @param _trustedMinter whitelisted address
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _maxPublicMints the max number of public sale mints on this chain
    constructor(
      address _trustedMinter,
      string memory _name,
      string memory _symbol,
      address _layerZeroEndpoint,
      uint _maxPublicMints
    ) ONFT721(_name, _symbol, _layerZeroEndpoint) {
        maxPublicMints = _maxPublicMints;
        trustedMinter = _trustedMinter;
    }

    /// @notice Mint your ONFT
    function mint(uint256 number, address receiver) external {
        require(msg.sender == trustedMinter, "Not authorized");
        require(publicMints + number - 1 <= maxPublicMints, "ONFT: Max Mint limit reached");

        uint256 newId;

        for (uint i = 0; i < number; ++i) {
            newId = nextMintId;
            nextMintId++;
            _safeMint(receiver, newId);
        }
    }

    /// @notice Mint admin NFTs
    function adminMint() external onlyOwner {
        uint newId = nextMintId;
        nextMintId++;
        _safeMint(msg.sender, newId);
    }

    /// @notice Set trusted minter
    function adminSetTrustedMinter(address minter) external onlyOwner {
        trustedMinter = minter;
    }
}
