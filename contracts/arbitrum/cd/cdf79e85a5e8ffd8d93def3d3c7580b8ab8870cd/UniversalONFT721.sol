// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ONFT721.sol";

/// @title Interface of the UniversalONFT standard
contract UniversalONFT721 is ONFT721 {
    uint public nextMintId;
    uint public maxMintId;
    uint public fee;
    /// @notice Constructor for the UniversalONFT
    /// @param _name the name of the token
    /// @param _symbol the token symbol
    /// @param _layerZeroEndpoint handles message transmission across chains
    /// @param _startMintId the starting mint number on this chain
    /// @param _endMintId the max number of mints on this chain
    constructor(string memory _name, string memory _symbol, uint256 _minGasToTransfer, address _layerZeroEndpoint, uint _startMintId, uint _endMintId, uint _fees) ONFT721(_name, _symbol, _minGasToTransfer, _layerZeroEndpoint) {
        nextMintId = _startMintId;
        maxMintId = _endMintId;
        fee = _fees * 1 wei;
    }

    /// @notice Mint your ONFT
    function mint() external payable {
        require(nextMintId <= maxMintId, "UniversalONFT721: max mint limit reached");
        require(msg.value >= fee, "Not enough ether sent, Minimm 0.001ether to mint");   
        uint newId = nextMintId;
        nextMintId++;

        _safeMint(msg.sender, newId);
    }

    

      function updateFees(uint256 _newFeesInEther) external onlyOwner() {
        fee = _newFeesInEther * 1 wei; // Convert fees from Ether to Wei
    }
   
    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }
}

