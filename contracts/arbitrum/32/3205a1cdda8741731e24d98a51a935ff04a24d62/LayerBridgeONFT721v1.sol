// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./ONFT721.sol";

contract LayerBridgeONFT721v1 is ONFT721 {
    // Everychain is having a different divisionRemainder. Each is a result of that chain token's id % 20. So max is support 20 chains.
    uint public constant MAXIMUM_DIVISION_REMAINDER = 20;
    uint public divisionRemainder;
    uint public nextMintId = 1;
    uint public systemFee;

    constructor(
        string memory _name, 
        string memory _symbol, 
        uint256 _minGasToTransfer, 
        address _layerZeroEndpoint, 
        uint _divisionRemainder, 
        uint _systemFee
    ) ONFT721(_name, _symbol, _minGasToTransfer, _layerZeroEndpoint) {
        divisionRemainder = _divisionRemainder;
        systemFee = _systemFee;
    }

    // Mint ONFT
    function mint() external payable {

        require(msg.value == systemFee, "Wrong system fee");

        uint newId = nextMintId*MAXIMUM_DIVISION_REMAINDER + divisionRemainder;
        nextMintId++;
        
        _safeMint(msg.sender, newId);
    }

    function withdrawSystemFee() external onlyOwner{
        payable(msg.sender).transfer(address(this).balance);
    }

    function changeSystemFee(
        uint _newSystemFee
    ) external onlyOwner{
        systemFee = _newSystemFee;
    }   
}

