// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./AdminControl.sol";
import "./ResolverCache.sol";
import "./IOFMWhitelistStrategyManager.sol";
import "./OFMConstants.sol";

contract OFMWhitelistStrategyManager is IOFMWhitelistStrategyManager, AdminControl, ResolverCache {

	mapping(bytes32 => mapping(address => bool)) private _whitelists;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
	function initialize(address resolver_) external initializer {
		__AdminControl_init_unchained(_msgSender());
		__ResolverCache_init(resolver_);
	}

	function setWhitelist(bytes32 poolId_, address[] calldata whitelist_) external virtual override {
		require(_msgSender() == _openFundMarket(), "only OFM");
		for (uint256 i = 0; i < whitelist_.length; i++) {
			_whitelists[poolId_][whitelist_[i]] = true;
		}
	}

	function isWhitelisted(bytes32 poolId_, address subscriber_) external view virtual override returns (bool) {
		return _whitelists[poolId_][subscriber_];
	}

	function _openFundMarket() internal view returns(address) {
		return getRequiredAddress(OFMConstants.CONTRACT_OFM, "WhitelistStrategyManager: OFM not set");
	}

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](1);
		newAddresses[0] = OFMConstants.CONTRACT_OFM;
		return _combineArrays(existAddresses, newAddresses);
	}
}
