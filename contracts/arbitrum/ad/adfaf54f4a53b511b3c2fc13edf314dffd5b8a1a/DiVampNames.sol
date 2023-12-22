// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AccessControl.sol";
//remove
import "./console.sol";

interface IDiVamps {
	function ownerOf(uint256 tokenId) external view returns (address);
}

contract DiVampNames is AccessControl {
	IDiVamps public diVamps;

	struct NameCollectionUpdate {
    uint256 key;
    string value;
  }

	mapping(uint256 => string) public titles;
	mapping(uint256 => string) public firstNames;
	mapping(uint256 => string) public lastNames;

	mapping(uint256 => uint256[3]) names;

	event SetName(
		address indexed sender,
		uint256 tokenId,
		string name
	);

	bytes32 public constant NAME_MANAGER_ROLE = keccak256("NAME_MANAGER_ROLE");

	constructor(address _diVamps) {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(NAME_MANAGER_ROLE, msg.sender);

		diVamps = IDiVamps(_diVamps);
	}

	function getName(uint256 _tokenId) public view returns (string memory) {
		string memory title = titles[names[_tokenId][0]];
		string memory firstName = firstNames[names[_tokenId][1]];
		string memory lastName = lastNames[names[_tokenId][2]];

		bool titleAssigned = bytes(title).length > 0;
		string memory optionalSpace = titleAssigned ? " " : "";

		return string.concat(title, optionalSpace, firstName, " ", lastName);
	}

	function setName(uint256 _tokenId, uint256[3] calldata _name) external {
		require(msg.sender == address(diVamps) || diVamps.ownerOf(_tokenId) == msg.sender, "Caller must be token owner");

		require(_name[0] == 0 || bytes(titles[_name[0]]).length != 0, "Invalid title");
		require(bytes(firstNames[_name[1]]).length != 0, "Invalid first name");
		require(bytes(lastNames[_name[2]]).length != 0, "Invalid last name");

		names[_tokenId] = _name;
		emit SetName(msg.sender, _tokenId, getName(_tokenId));
	}

	function updateNameCollection(
		NameCollectionUpdate[] calldata _titles,
		NameCollectionUpdate[] calldata _firstNames,
		NameCollectionUpdate[] calldata _lastNames
	) external onlyRole(NAME_MANAGER_ROLE) {
		for (uint256 i = 0; i < _titles.length; i++) {
			uint256 newKey = _titles[i].key;
			string calldata newTitle = _titles[i].value;

			require(newKey != 0, "Title key 0 is reserved");
			require(bytes(newTitle).length != 0, "Invalid title");

			titles[newKey] = newTitle;
		}

		for (uint256 i = 0; i < _firstNames.length; i++) {
			uint256 newKey = _firstNames[i].key;
			string calldata newFirstName = _firstNames[i].value;

			require(bytes(newFirstName).length != 0, "Invalid first name");

			firstNames[newKey] = newFirstName;
		}

		for (uint256 i = 0; i < _lastNames.length; i++) {
			uint256 newKey = _lastNames[i].key;
			string calldata newLastName = _lastNames[i].value;

			require(bytes(newLastName).length != 0, "Invalid last name");

			lastNames[newKey] = newLastName;
		}
	}

	function getNameKeys(uint256 _tokenId) public view returns (uint256[3] memory) {
		return names[_tokenId];
	}
}

