// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SFTMintableConcrete.sol";
import "./MultiRechargeableConcrete.sol";
import "./IUnderwriterProfitConcrete.sol";

contract UnderwriterProfitConcrete is IUnderwriterProfitConcrete, SFTMintableConcrete, MultiRechargeableConcrete  {
	mapping(uint256 => UnderwriterProfitSlotInfo) internal _slotInfos;

	function initialize() external initializer {
		__SFTMintableConcrete_init();
	}

	function getSlot(string memory name_, address currency_) public view virtual override returns (uint256) {
		uint256 chainId;
        assembly {
            chainId := chainid()
        }

		return uint256(keccak256(abi.encodePacked(chainId, delegate(), name_, currency_)));
	}

	function slotBaseInfo(uint256 slot_) public view virtual override returns (UnderwriterProfitSlotInfo memory) {
		return _slotInfos[slot_];
	}

	function _isSlotValid(uint256 slot_) view internal virtual override returns (bool) {
		return _slotInfos[slot_].isValid;
	}

	function _createSlot(address /** txSender_ */, bytes memory inputSlotInfo_) internal virtual override returns (uint256 slot_) {
		InputSlotInfo memory inputSlotInfo = abi.decode(inputSlotInfo_, (InputSlotInfo));
		UnderwriterProfitSlotInfo memory slotInfo = UnderwriterProfitSlotInfo(inputSlotInfo.name, inputSlotInfo.currency, true);
		slot_ = getSlot(slotInfo.name, slotInfo.currency);
		_slotInfos[slot_] = slotInfo;
	}
	
	function _mint(address txSender_, address mintTo_, uint256 slot_, uint256 tokenId_, uint256 value_) internal virtual override {}

    function _currency(uint256 slot_) internal view virtual override returns (address) {
        return _slotInfos[slot_].currency;
    }
}
