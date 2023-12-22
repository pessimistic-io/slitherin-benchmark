pragma solidity ^0.8.0;

import "./ERC1155PresetMinterPauser.sol";

contract JoyNFT is ERC1155PresetMinterPauser {
	string public name;
	string public symbol;
    
	constructor(string memory _name, string memory _symbol, string memory uri) ERC1155PresetMinterPauser(uri) {
		name = _name;
		symbol = _symbol;
	}
}
