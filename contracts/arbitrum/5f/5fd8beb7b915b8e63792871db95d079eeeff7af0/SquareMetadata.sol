//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./ISquareMetadata.sol";
import "./SquareMetadataState.sol";

contract SquareMetadata is Initializable, SquareMetadataState, ISquareMetadata {
	using StringsUpgradeable for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	function initialize() external initializer {
		SquareMetadataState.__SquareMetadataState_init();
	}

	function setBaseURI(string calldata _baseURI)
		override
		external
		onlyAdminOrOwner
	{
		baseURI = _baseURI;
	}

	function tokenURI(uint256 _tokenId) 
		override
		external
		view
		returns(string memory)

	{   
		string memory re;
		if (revealed) {
			re = 'revealed';
		} else {
			re = 'unrevealed';
		}
		return string(abi.encodePacked(baseURI ,_tokenId.toString(), '.json'));
	}

	function setRevealed(bool _revealed)
		external
		onlyAdminOrOwner
	{
		revealed = _revealed;
	}

	function addSquareContract(address _squareAddress)
		public 
		onlyAdminOrOwner
	{
		squares.add(_squareAddress);
	}

	function removeSquareContract(address _squareAddress)
		public 
		onlyAdminOrOwner 
	{
		squares.remove(_squareAddress);
	}

	function isSquare(address _squareAddress)
		external
		view
		returns (bool)
	{
		return squares.contains(_squareAddress);
	}

	modifier onlySquare() {
		require(squares.contains(msg.sender), "Metadata: Not a square contract");

		_;
	}
}
