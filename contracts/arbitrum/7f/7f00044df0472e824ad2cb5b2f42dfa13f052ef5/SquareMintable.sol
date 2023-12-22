//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";

import "./SquareContracts.sol";

abstract contract SquareMintable is Initializable, SquareContracts {
    using CountersUpgradeable for CountersUpgradeable.Counter;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    function __SquareMintable_init() internal initializer {
		SquareContracts.__SquareContracts_init();
	}

    function mint(address _to, 
                  uint256 _amount)
        external
        onlyAdminOrOwner
        contractsAreSet
    {
        require(
			maxSupply >= totalSupply() + _amount,
			"SquareMintable: Max supply reached"
		);
        
        for (uint256 i = 0; i < _amount; i++) {
            _mint(_to);
        }
    }

	function _mint(address _to)
		private
	{
		uint256 _tokenId = tokenIdCounter.current();
		_safeMint(_to, _tokenId);
        emit SquareMinted(_to, _tokenId);
        tokenIdCounter.increment();
	}

	function addMinter(address _minter) 
        external 
        onlyAdminOrOwner 
    {
		minters.add(_minter);
	}

	function removeMinter(address _minter) 
        external 
        onlyAdminOrOwner 
    {
		minters.remove(_minter);
	}

	function isMinter(address _minter) 
        external 
        view 
        returns (bool) 
    {
		return minters.contains(_minter);
	}

	modifier onlyMinter() {
		require(minters.contains(msg.sender), "Square: Not a minter");

		_;
	}

	function totalSupply() public view returns (uint256) {
		return tokenIdCounter.current();
	}

    function areSquaresFilled()
        external
        override
        view
        returns (bool)
    {
        return tokenIdCounter.current() == maxSupply;
    }
}
