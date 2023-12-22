//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";

import "./BarnContracts.sol";

abstract contract BarnMintable is Initializable, BarnContracts {
	using CountersUpgradeable for CountersUpgradeable.Counter;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	function __BarnMintable_init() internal initializer {
		BarnContracts.__BarnContracts_init();
		tokenIdCounter.increment();
	}

	function mint(address _to, uint256 _amount)
		external
		override
		whenNotPaused
		onlyMinter
	{
		require(
			maxSupply >= totalSupply() + _amount,
			"Barn: Max supply reached"
		);
		require(
			randomRequestLimit > 0,
			"Barn: Random request limit not set"
		);

		for (uint256 i = 0; i < _amount; i++) {
			uint256 _tokenId = tokenIdCounter.current();
			uint256 ranNum = generateRandomNumber(_tokenId);
			barnMetadata.setBarnType(_tokenId,ranNum);
			_safeMint(_to, _tokenId);
			emit GeneratedRandomNumber(_tokenId, ranNum);
			tokenIdCounter.increment();
		}
	}

	function setRandomRequestLimit(uint256 _randomRequestLimit) external onlyAdminOrOwner {
		require(
			_randomRequestLimit >= randomRequestLimit,
			"New random request limit is less than old request limit"
		);

		randomRequestLimit = _randomRequestLimit;
	}

	function generateRandomNumber(uint256 _tokenId) private view returns (uint256) {
		// Adds some arbitrary, mod is upper bound on random requested
		uint256 timeStamp = block.timestamp;
		uint256 requestId = (_tokenId * timeStamp) % randomRequestLimit;
		//Probably store tokenId => requestId mapping
		return randomizer.isRandomReady(requestId) ? randomizer.revealRandomNumber(requestId) : generateLocalRandomNumber();
	}

	function generateLocalRandomNumber() private view returns (uint256) {
		return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty)));
	}

	function addMinter(address _minter) external onlyAdminOrOwner {
		minters.add(_minter);
	}

	function removeMinter(address _minter) external onlyAdminOrOwner {
		minters.remove(_minter);
	}

	function isMinter(address _minter) external view returns (bool) {
		return minters.contains(_minter);
	}

	modifier onlyMinter() {
		require(minters.contains(msg.sender), "Not a minter");

		_;
	}

	function totalSupply() public view returns (uint256) {
		return tokenIdCounter.current() - amountBurned;
	}
}
