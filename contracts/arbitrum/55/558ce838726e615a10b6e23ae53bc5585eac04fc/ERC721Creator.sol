// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Proxy.sol";
import "./Address.sol";
import "./StorageSlot.sol";
import "./Ownable.sol";
contract ERC721Creator is Proxy, Ownable {

    struct SalesConfiguration {
        uint256 publicSalePrice;
        uint256 maxSalePurchasePerAddress;
        uint256 publicSaleStart;
        uint256 publicSaleEnd;
        uint256 presaleStart;
        uint256 preSalePrice;
        uint256 presaleMaxMintsPerAddress;
        uint256 presaleEnd;
        bytes32 presaleMerkleRoot;
        address fundsRecipient;
    }
    constructor(string memory name, string memory symbol, uint256 maxSupply, string memory baseURI, string memory collectionURI, address recipient, uint256 royaltyAmount,
SalesConfiguration memory _salesConfig


) Ownable() {
        assert(_IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = 0xE1F32f730166bE0766E6023A13fCB155ac495567;


    Address.functionDelegateCall(
            0xE1F32f730166bE0766E6023A13fCB155ac495567,
            abi.encodeWithSignature("initCreator(string,string,uint256,string,string,address,uint256,uint256,uint256)",
                                                name, symbol, maxSupply, baseURI, collectionURI, recipient, royaltyAmount, 100000000000000, 1696089600));

        Address.functionDelegateCall(
            0xE1F32f730166bE0766E6023A13fCB155ac495567,
            abi.encodeWithSignature("setSaleConfiguration(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,address,bytes32)",
                _salesConfig.publicSalePrice,
                _salesConfig.maxSalePurchasePerAddress,
                _salesConfig.publicSaleStart,
                _salesConfig.publicSaleEnd,
                _salesConfig.presaleStart,
                _salesConfig.presaleEnd,
                _salesConfig.preSalePrice,
                _salesConfig.presaleMaxMintsPerAddress,
                _salesConfig.fundsRecipient,
                _salesConfig.presaleMerkleRoot
            )
        );
    }

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() public view returns (address) {
        return _implementation();
    }

    function _implementation() internal override view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

}

