// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./BitMaps.sol";
import "./ERC721Psi.sol";

abstract contract ERC721PsiAddressData is ERC721Psi {
    mapping(address => AddressData) _addressData;

    // Compiler will pack this into a single 256bit word.
    struct AddressData {
        uint64 balance;
        uint64 numberMinted;
        uint64 numberBurned;
        uint64 aux;
    }

    function balanceOf(address _owner)
    public
    view
    virtual
    override
    returns (uint)
    {
        return uint256(_addressData[_owner].balance);
    }

    function mintedOf(address _owner)
    public
    view
    virtual
    returns (uint)
    {
        return uint256(_addressData[_owner].numberMinted);
    }

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal override virtual {
        require(quantity < 2 ** 64);
        uint64 _quantity = uint64(quantity);

        if(from != address(0)){
            _addressData[from].balance -= _quantity;
        } else {
            // Mint
            _addressData[to].numberMinted += _quantity;
        }

        if(to != address(0)){
            _addressData[to].balance += _quantity;
        } else {
            // Burn
            _addressData[from].numberBurned += _quantity;
        }
        super._afterTokenTransfers(from, to, startTokenId, quantity);
    }
}

