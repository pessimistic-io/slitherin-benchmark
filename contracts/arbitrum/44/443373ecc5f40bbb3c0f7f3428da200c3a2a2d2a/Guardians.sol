// SPDX-License-Identifier: undefined
pragma solidity ^0.8.0;

import "./ERC1155Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";

contract Guardian is ERC1155Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    mapping(uint256 => bool) internal _minted;

    function initialize() initializer virtual public {
        __ERC1155_init("ipfs://bafkreigivzaby4datuiehg2zmb6zznfyu5ydh54exjjxtkukusoantjxsm/");
        __Ownable_init();
        __UUPSUpgradeable_init();

     }

     function _authorizeUpgrade(address) internal override onlyOwner{

}
 function mint(uint256 supply, uint256 id) onlyOwner external  {
        require(_minted[id] == false,"ID have already been minted, you can not add to the supply.");
        _minted[id]=true;
        _mint(msg.sender, id, supply, ""); 
    }

    function setURI(string memory newuri) onlyOwner external 
    {
        _setURI(newuri);
    }
}
