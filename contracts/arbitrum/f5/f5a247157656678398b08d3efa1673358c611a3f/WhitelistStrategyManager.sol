// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Constants.sol";
import "./AdminControl.sol";
import "./ResolverCache.sol";
import "./IWhitelistStrategyManager.sol";

contract WhitelistStrategyManager is IWhitelistStrategyManager, AdminControl, ResolverCache {

	mapping(bytes32 => mapping(address => bool)) private _whitelists;

	function initialize(address resolver_) external initializer {
		__AdminControl_init_unchained(_msgSender());
		__ResolverCache_init(resolver_);
	}

	function setWhitelist(bytes32 issueKey_, address[] calldata whitelist_) external virtual override {
		require(_msgSender() == _issueMarket(), "only issue market");
		for (uint256 i = 0; i < whitelist_.length; i++) {
			_whitelists[issueKey_][whitelist_[i]] = true;
		}
	}

	function isWhitelisted(bytes32 issueKey_, address buyer_) external view virtual override returns (bool) {
		return _whitelists[issueKey_][buyer_];
	}

	function _issueMarket() internal view returns(address) {
		return getRequiredAddress(Constants.CONTRACT_ISSUE_MARKET, "WhitelistStrategyManager: Issue market not set");
	}

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](1);
		newAddresses[0] = Constants.CONTRACT_ISSUE_MARKET;
		return _combineArrays(existAddresses, newAddresses);
	}
}
