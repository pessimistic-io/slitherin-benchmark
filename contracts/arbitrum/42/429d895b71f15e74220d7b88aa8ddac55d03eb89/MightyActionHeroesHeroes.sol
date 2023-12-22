/*
 * Copyright (c) 2023 Mighty Bear Games
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MightyNetERC721Upgradeable.sol";

contract MightyActionHeroesHeroes is MightyNetERC721Upgradeable {
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		string memory baseURI_,
		string memory contractURI_,
		IOperatorFilterRegistry operatorFilterRegistry_,
		IRestrictedRegistry restrictedRegistry_
	) public initializer {
		__MightyNetERC721Upgradeable_init(
			baseURI_,
			contractURI_,
			operatorFilterRegistry_,
			restrictedRegistry_,
			"Mighty Action Heroes Heroes",
			"MAHH"
		);
	}
}

