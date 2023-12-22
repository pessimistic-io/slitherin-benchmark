//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**   ███╗   ███╗███████╗██████╗ ██╗ ██████╗██╗███╗   ██╗ █████╗ ██╗
 *    ████╗ ████║██╔════╝██╔══██╗██║██╔════╝██║████╗  ██║██╔══██╗██║
 *    ██╔████╔██║█████╗  ██║  ██║██║██║     ██║██╔██╗ ██║███████║██║
 *    ██║╚██╔╝██║██╔══╝  ██║  ██║██║██║     ██║██║╚██╗██║██╔══██║██║
 *    ██║ ╚═╝ ██║███████╗██████╔╝██║╚██████╗██║██║ ╚████║██║  ██║███████╗
 *    ╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝ ╚═════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
 *
 *    ███╗   ███╗ █████╗ ███████╗███████╗
 *    ████╗ ████║██╔══██╗██╔════╝██╔════╝
 *    ██╔████╔██║███████║███████╗███████╗
 *    ██║╚██╔╝██║██╔══██║╚════██║╚════██║
 *    ██║ ╚═╝ ██║██║  ██║███████║███████║
 *    ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝
 *
 *    ███╗   ███╗███████╗██████╗ ██╗ █████╗
 *    ████╗ ████║██╔════╝██╔══██╗██║██╔══██╗
 *    ██╔████╔██║█████╗  ██║  ██║██║███████║
 *    ██║╚██╔╝██║██╔══╝  ██║  ██║██║██╔══██║
 *    ██║ ╚═╝ ██║███████╗██████╔╝██║██║  ██║
 *    ╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝
 */

import "./ERC2981ContractWideRoyalties.sol";
import "./TokenRescuer.sol";
import "./ERC1155URIStorage.sol";

/**
 * @title Medicinal Mass Media
 * @author Aaron Hanson <coffee.becomes.code@gmail.com> @CoffeeConverter
 * @notice https://medicinalmass.com/
 */
contract MedicinalMassMedia is
    ERC1155URIStorage,
    ERC2981ContractWideRoyalties,
    TokenRescuer
{
    /// The contract URI for contract-level metadata.
    string public contractURI;

    constructor(
        string memory _contractURI,
        address _royaltiesReceiver
    )
        ERC1155("")
    {
        contractURI = _contractURI;
        setRoyalties(
            _royaltiesReceiver,
            666
        );
    }

    /**
     * @notice (only owner) Mints tokens to a list of recipients.
     * @param _tokenId The token ID to mint.
     * @param _recipients The list of token recipients.
     */
    function administerMedicine(
        uint256 _tokenId,
        address[] calldata _recipients
    )
        external
        onlyOwner
    {
        unchecked {
            for (uint i; i < _recipients.length; ++i) {
                _mint(
                    _recipients[i],
                    _tokenId,
                    1,
                    ""
                );
            }
        }
    }

    /**
     * @notice (only owner) Mints tokens to a list of recipients and sets URI.
     * @param _tokenId The token ID to mint.
     * @param _tokenURI The token URI.
     * @param _recipients The list of token recipients.
     */
    function administerMedicine(
        uint256 _tokenId,
        string calldata _tokenURI,
        address[] calldata _recipients
    )
        external
        onlyOwner
    {
        _setURI(_tokenId, _tokenURI);
        unchecked {
            for (uint i; i < _recipients.length; ++i) {
                _mint(
                    _recipients[i],
                    _tokenId,
                    1,
                    ""
                );
            }
        }
    }

    /**
     * @notice (only owner) Sets the contract URI for contract metadata.
     * @param _newContractURI The new contract URI.
     */
    function setContractURI(
        string calldata _newContractURI
    )
        external
        onlyOwner
    {
        contractURI = _newContractURI;
    }

    /**
     * @notice (only owner) Sets a token-specific metadata URI.
     * @param _tokenId The token ID.
     * @param _tokenURI The new URI.
     */
    function setTokenURI(
        uint256 _tokenId,
        string calldata _tokenURI
    )
        external
        onlyOwner
    {
        _setURI(_tokenId, _tokenURI);
    }

    /**
     * @notice (only owner) Sets a base URI for token-specific metadata URIs.
     * @param _tokenBaseURI The new token base URI.
     */
    function setTokenBaseURI(
        string calldata _tokenBaseURI
    )
        external
        onlyOwner
    {
        _setBaseURI(_tokenBaseURI);
    }

    /**
     * @notice (only owner) Sets the URI for token metadata.
     * @param _newURI The new URI.
     */
    function setURI(
        string calldata _newURI
    )
        external
        onlyOwner
    {
        _setURI(_newURI);
    }

    /**
     * @notice (only owner) Sets ERC-2981 royalties recipient and percentage.
     * @param _recipient The address to which to send royalties.
     * @param _value The royalties percentage (two decimals, e.g. 1000 = 10%).
     */
    function setRoyalties(
        address _recipient,
        uint256 _value
    )
        public
        onlyOwner
    {
        _setRoyalties(
            _recipient,
            _value
        );
    }

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        override (ERC1155, ERC2981Base)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

}

