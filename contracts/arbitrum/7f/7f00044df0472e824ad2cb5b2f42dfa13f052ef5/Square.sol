//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./CountersUpgradeable.sol";

import "./SquareMintable.sol";
import "./ISquare.sol";

contract Square is 
    Initializable, 
    ISquare, 
    SquareMintable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
	
	function initialize() external initializer {
		SquareMintable.__SquareMintable_init();
	}

    function adminSafeTransferFrom(address _from,
                                   address _to,
		                           uint256 _tokenId) 
        external 
        override 
        onlyAdminOrOwner 
    {
		_safeTransfer(_from, _to, _tokenId, "");
	}

    function tokenURI(uint256 _tokenId)
		public
		view
		override
		contractsAreSet
		returns (string memory)
	{
		require(_exists(_tokenId), "Square: Token does not exist");

		return squareMetadata.tokenURI(_tokenId);
	}
}
