// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { FullMath as Math } from "./FullMath.sol";
import { IShareable } from "./IShareable.sol";

abstract contract Shareable is IShareable {
	uint256 public share; // crops per gem    [ray]
	uint256 public stock; // crop balance     [wad]
	uint256 public totalWeight; // [wad]

	//LockID => Value
	mapping(uint256 => uint256) internal crops; // [wad]
	mapping(uint256 => uint256) internal userShares; // [wad]

	uint256[49] private __gap;

	function _crop() internal virtual returns (uint256);

	function _addShare(uint256 _lockId, uint256 _value) internal virtual {
		if (_value > 0) {
			uint256 wad = Math.wdiv(_value, netAssetsPerShareWAD());
			require(int256(wad) > 0);

			totalWeight += wad;
			userShares[_lockId] += wad;
		}
		crops[_lockId] = Math.rmulup(userShares[_lockId], share);
		emit ShareUpdated(_value);
	}

	function _partialExitShare(uint256 _lockId, uint256 _newShare)
		internal
		virtual
	{
		_exitShare(_lockId);
		_addShare(_lockId, _newShare);
	}

	function _exitShare(uint256 _lockId) internal virtual {
		uint256 value = userShares[_lockId];

		if (value > 0) {
			uint256 wad = Math.wdivup(value, netAssetsPerShareWAD());

			require(int256(wad) > 0);

			totalWeight -= wad;
			userShares[_lockId] -= wad;
		}

		crops[_lockId] = Math.rmulup(userShares[_lockId], share);
		emit ShareUpdated(value);
	}

	function netAssetsPerShareWAD() public view override returns (uint256) {
		return
			(totalWeight == 0) ? Math.WAD : Math.wdiv(totalWeight, totalWeight);
	}

	function getCropsOf(uint256 _lockId)
		external
		view
		override
		returns (uint256)
	{
		return crops[_lockId];
	}

	function getShareOf(uint256 _lockId)
		public
		view
		override
		returns (uint256)
	{
		return userShares[_lockId];
	}
}


