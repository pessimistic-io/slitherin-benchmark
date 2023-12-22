//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./CountersUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./ISquare.sol";
import "./ISquareMetadata.sol";
import "./AdminableUpgradeable.sol";
import "./IRandomizer.sol";

abstract contract SquareState is
    Initializable, 
	ISquare, 
	ERC721Upgradeable,
	AdminableUpgradeable
{
	using CountersUpgradeable for CountersUpgradeable.Counter;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
	event SquareMinted(address _owner, uint256 _tokenId);

	CountersUpgradeable.Counter internal tokenIdCounter;
	EnumerableSetUpgradeable.AddressSet internal minters;
	ISquareMetadata public squareMetadata;

	uint256 public maxSupply;

	function __SquareState_init() internal initializer {
		AdminableUpgradeable.__Adminable_init();
		ERC721Upgradeable.__ERC721_init("Fuego SquaresZ", "FUEGO_SQUARE");

		maxSupply = 100;
	}
}
