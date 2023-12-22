// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import { IRestrictedRegistry } from "./IRestrictedRegistry.sol";

abstract contract ERC721Restrictable is Initializable, ERC721Upgradeable {
	error TokenIsRestricted(uint256 tokenId);
	IRestrictedRegistry public restrictedRegistry;

	function __ERC721Restrictable_init(IRestrictedRegistry restrictedRegistry_)
		internal
		onlyInitializing
	{
		__ERC721Restrictable_init_unchained(restrictedRegistry_);
	}

	function __ERC721Restrictable_init_unchained(
		IRestrictedRegistry restrictedRegistry_
	) internal onlyInitializing {
		_setRestrictedRegistry(restrictedRegistry_);
	}

	function _setRestrictedRegistry(IRestrictedRegistry restrictedRegistry_)
		internal
	{
		restrictedRegistry = restrictedRegistry_;
	}

	modifier onlyAllowUnrestricted(uint256 tokenId) {
		if (restrictedRegistry.isRestricted(address(this), tokenId)) {
			revert TokenIsRestricted(tokenId);
		}
		_;
	}

	function exists(uint256 tokenId) external view virtual returns (bool) {
		return _exists(tokenId);
	}

	uint256[50] private __gap;
}

