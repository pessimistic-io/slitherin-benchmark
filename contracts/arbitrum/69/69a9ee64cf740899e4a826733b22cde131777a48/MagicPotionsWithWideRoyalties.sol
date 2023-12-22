// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MagicNFT.sol";
import "./ERC2981ContractWideRoyalties.sol";

contract MagicPotionsWithWideRoyalties is ERC2981ContractWideRoyalties, MagicNFT {

    constructor(
        address magicToken,
        address revenueRecipient,
        uint256 _whitelistStart,
        uint256 _whitelistEnd,
        uint256 _reserveListStart,
        uint256 _reserveListEnd,
        uint256 _publicSaleStart,
        string memory tempUri
    ) MagicNFT(
        magicToken, 
        revenueRecipient, 
        _whitelistStart, 
        _whitelistEnd,
        _reserveListStart,
        _reserveListEnd,
        _publicSaleStart,
        tempUri
    ) { }


    /// @notice Allows to set the royalties on the contract
    /// @dev This function in a real contract should be protected with a onlyOwner (or equivalent) modifier
    /// @param recipient the royalties recipient
    /// @param value royalties value (between 0 and 10000)
    function setRoyalties(address recipient, uint256 value) public onlyOwner {
        _setRoyalties(recipient, value);
    }

        /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(MagicNFT, ERC2981Base)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
