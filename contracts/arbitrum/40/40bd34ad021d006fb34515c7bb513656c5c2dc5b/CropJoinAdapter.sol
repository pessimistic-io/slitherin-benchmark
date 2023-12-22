// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ICropJoinAdapter.sol";

import { FullMath } from "./FullMath.sol";
import { IERC20 } from "./IERC20.sol";
import { IVatLike } from "./IVatLike.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

abstract contract CropJoinAdapter is ICropJoinAdapter, OwnableUpgradeable {
	string public name;

	uint256 public share; // crops per gem    [ray]
	uint256 public stock; // crop balance     [wad]
	uint256 public totalWeight; // [wad]

	//User => Value
	mapping(address => uint256) public crops; // [wad]
	mapping(address => uint256) public userShares; // [wad]

	uint256 public interestMinted;

	uint256[49] private __gap;

	function __INIT_ADAPTOR(string memory _moduleName)
		internal
		onlyInitializing
	{
		__Ownable_init();

		name = _moduleName;
	}

	function shareOf(address owner) public view override returns (uint256) {
		return userShares[owner];
	}

	function netAssetsPerShareWAD() public view returns (uint256) {
		return
			(totalWeight == 0)
				? FullMath.WAD
				: FullMath.wdiv(totalWeight, totalWeight);
	}

	function _crop() internal virtual returns (uint256) {
		return interestMinted - stock;
	}

	function _addShare(address urn, uint256 val) internal virtual {
		if (val > 0) {
			uint256 wad = FullMath.wdiv(val, netAssetsPerShareWAD());

			require(int256(wad) > 0);

			totalWeight += wad;
			userShares[urn] += wad;
		}
		crops[urn] = FullMath.rmulup(userShares[urn], share);
		emit Join(val);
	}

	function _exitShare(address guy, uint256 val) internal virtual {
		if (val > 0) {
			uint256 wad = FullMath.wdivup(val, netAssetsPerShareWAD());

			require(int256(wad) > 0);

			totalWeight -= wad;
			userShares[guy] -= wad;
		}
		crops[guy] = FullMath.rmulup(userShares[guy], share);
		emit Exit(val);
	}
}


