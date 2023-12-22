//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IBarn.sol";
import "./AdminableUpgradeable.sol";
import "./IBarnMetadata.sol";
import "./IRandomizer.sol";

abstract contract BarnState is 
	Initializable, 
	IBarn, 
	ERC721Upgradeable,
	AdminableUpgradeable
{
	using CountersUpgradeable for CountersUpgradeable.Counter;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
	event GeneratedRandomNumber(uint256 _tokenId, uint256 _randomNumber);


	CountersUpgradeable.Counter internal tokenIdCounter;

	EnumerableSetUpgradeable.AddressSet internal minters;

	IBarnMetadata public barnMetadata;
	IRandomizer public randomizer;

	uint256 public amountBurned;
	uint256 public maxSupply;
	uint256 public randomRequestLimit;

	function __BarnState_init() internal initializer {
		AdminableUpgradeable.__Adminable_init();
		ERC721Upgradeable.__ERC721_init("Lost Barn", "LOST_BARN");

		maxSupply = 25000;
	}
}
