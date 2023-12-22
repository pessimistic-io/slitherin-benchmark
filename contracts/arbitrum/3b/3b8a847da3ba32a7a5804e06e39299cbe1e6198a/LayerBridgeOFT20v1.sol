// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFTV2.sol";

/// @title A LayerZero OmnichainFungibleToken example of BasedOFT
/// @notice Use this contract only on the BASE CHAIN. It locks tokens on source, on outgoing send(), and unlocks tokens when receiving from other chains.
contract  LayerBridgeOFT20v1 is OFTV2 {

    uint public systemFee;
    
    constructor(
        string memory _name, 
        string memory _symbol, 
        address _layerZeroEndpoint, 
        uint _initialSupply, 
        uint8 _sharedDecimals,
        uint _systemFee
    ) OFTV2(_name, _symbol, _sharedDecimals, _layerZeroEndpoint) {
        systemFee = _systemFee;
        _mint(_msgSender(), _initialSupply);
    }

    function claim(uint claimAmount) external payable {
        require(msg.value == systemFee, "Wrong system fee");
        _mint(msg.sender, claimAmount);
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

