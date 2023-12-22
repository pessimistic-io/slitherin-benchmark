// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BaseSFTConcreteUpgradeable.sol";
import "./ISFTMintableConcrete.sol";

abstract contract SFTMintableConcrete is ISFTMintableConcrete, BaseSFTConcreteUpgradeable {
	
	function __SFTMintableConcrete_init() internal onlyInitializing {
		__BaseSFTConcrete_init();
	}

    function createSlotOnlyDelegate(address txSender_, bytes calldata inputSlotInfo_) external virtual override onlyDelegate returns (uint256 slot_) {
		return _createSlot(txSender_, inputSlotInfo_);
	}

	function mintOnlyDelegate(address txSender_, address mintTo_, uint256 slot_, uint256 tokenId_, uint256 value_) external virtual override onlyDelegate {
		return _mint(txSender_, mintTo_, slot_, tokenId_, value_);
	}

	function _createSlot(address txSender_, bytes memory inputSlotInfo_) internal virtual returns (uint256 slot_);
	function _mint(address txSender_, address mintTo_, uint256 slot_, uint256 tokenId_, uint256 value_) internal virtual;

	uint256[50] private __gap;
}
