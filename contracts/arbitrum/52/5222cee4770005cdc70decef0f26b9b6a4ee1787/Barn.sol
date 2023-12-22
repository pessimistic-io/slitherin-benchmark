//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./BarnMintable.sol";
import "./IBarn.sol";

contract Barn is Initializable, IBarn, BarnMintable {
	using CountersUpgradeable for CountersUpgradeable.Counter;
	
	function initialize() external initializer {
		BarnMintable.__BarnMintable_init();
	}
	
	function setMaxSupply(uint256 _maxSupply) external override onlyAdminOrOwner {
		require(
			_maxSupply >= totalSupply(),
			"New max supply cannot be lower than current supply"
		);
		maxSupply = _maxSupply;
	}

	function adminSafeTransferFrom(
		address _from,
		address _to,
		uint256 _tokenId
	) external override onlyAdminOrOwner {
		_safeTransfer(_from, _to, _tokenId, "");
	}

	function tokenURI(uint256 _tokenId)
		public
		view
		override
		contractsAreSet
		returns (string memory)
	{
		require(_exists(_tokenId), "Barn: Token does not exist");

		return barnMetadata.tokenURI(_tokenId);
	}  

	function burn(uint256 _tokenId)
		external
		override
		onlyAdminOrOwner
		contractsAreSet
	{
		_burn(_tokenId);

		amountBurned++;
	}
}

