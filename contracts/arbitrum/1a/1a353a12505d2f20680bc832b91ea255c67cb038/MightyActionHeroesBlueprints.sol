// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MightyNetERC1155Upgradeable.sol";

contract MightyActionHeroesBlueprints is MightyNetERC1155Upgradeable {
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		string memory baseURI_,
		string memory contractURI_,
		IOperatorFilterRegistry operatorFilterRegistry_
	) public initializer {
		__MightyNetERC1155Upgradeable_init(
			baseURI_,
			contractURI_,
			operatorFilterRegistry_
		);
	}
}

