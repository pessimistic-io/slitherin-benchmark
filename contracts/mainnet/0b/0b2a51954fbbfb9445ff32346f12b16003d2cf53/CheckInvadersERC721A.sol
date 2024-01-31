// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./Base64.sol";
import "./Strings.sol";

import "./RevokableDefaultOperatorFiltererUpgradeable.sol";
import {ERC721AUpgradeable} from "./ERC721AUpgradeable.sol";
import {IContractToBurn} from "./IContractToBurn.sol";

contract CheckInvadersERC721A is
    OwnableUpgradeable,
    RevokableDefaultOperatorFiltererUpgradeable,
    ERC721AUpgradeable
{
    /*
      Errors
    */

    error MaxSupplyMinted();
    error CallerMustBeMinter();
    error InsufficientTokenstoBurn();
    error LMAO_nerds_always_have_to_read_contracts();

    /*
      Events
    */

    event UpdateTokenURIContract(address);
    event UpdateMaxEditions(uint256);
    event UpdateContractMetadata(string, string);
    event UpdateTokenImageURL(string);
    event UpdateTokenDescription(string);
    event UpdateContractToBurn(address);
    event UpdateQuantityToBurn(uint256);

    /*
      Storage
    */

    // The address of the contract we're burning
    address public CONTRACT_TO_BURN;
    // The number needed to burn 1
    uint256 public QTY_TO_BURN;

    // Contract version
    uint16 private _version;
    // Contract description
    string private _description;
    // Contract external link
    string private _externalLink;
    // Stored to serve in tokenURIs. Might be dynamic later XD
    string private _tokenImageURL;
    // Stored to serve in tokenURIs
    string private _tokenDescription;

    /*
      Initialization
    */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory description_,
        string memory externalLink_,
        string memory tokenImageURL_,
        string memory tokenDescription_,
        address contractToBurn_,
        uint256 qtyToBurn_
    ) public virtual initializer initializerERC721A {
        __ERC721A_init(name_, symbol_);
        __Ownable_init();
        __RevokableDefaultOperatorFilterer_init();
        setContractMetadata(description_, externalLink_);
        setTokenImageURL(tokenImageURL_);
        setTokenDescription(tokenDescription_);
        setContractToBurn(contractToBurn_);
        setQuantityToBurn(qtyToBurn_);
        _setVersion(0x1);
    }

    /*
      Public Setters
    */

    function setContractMetadata(
        string memory description_,
        string memory externalLink_
    ) public onlyOwner {
        _setContractDescription(description_);
        _setContractExternalLink(externalLink_);
        emit UpdateContractMetadata(description_, externalLink_);
    }

    function setTokenImageURL(string memory tokenImageURL_) public onlyOwner {
        _setTokenImageURL(tokenImageURL_);
        emit UpdateTokenImageURL(tokenImageURL_);
    }

    function setTokenDescription(
        string memory tokenDescription_
    ) public onlyOwner {
        _setTokenDescription(tokenDescription_);
        emit UpdateTokenDescription(tokenDescription_);
    }

    function setContractToBurn(address contractToBurn_) public onlyOwner {
        _setContractToBurn(contractToBurn_);
        emit UpdateContractToBurn(contractToBurn_);
    }

    function setQuantityToBurn(uint256 qtyToBurn_) public onlyOwner {
        _setQuantityToBurn(qtyToBurn_);
        emit UpdateQuantityToBurn(qtyToBurn_);
    }

    /*
      Getter functions
    */

    function version() public view returns (uint16) {
        return _version;
    }

    function description() public view returns (string memory) {
        return _description;
    }

    function externalLink() public view returns (string memory) {
        return _externalLink;
    }

    function tokenImageURL() public view returns (string memory) {
        return _tokenImageURL;
    }

    function tokenDescription() public view returns (string memory) {
        return _tokenDescription;
    }

    function owner()
        public
        view
        virtual
        override(OwnableUpgradeable, RevokableOperatorFiltererUpgradeable)
        returns (address)
    {
        return OwnableUpgradeable.owner();
    }

    /*
      Internal Setters
    */

    function _setVersion(uint16 version_) internal {
        _version = version_;
    }

    function _setContractDescription(string memory description_) internal {
        _description = description_;
    }

    function _setContractExternalLink(string memory externalLink_) internal {
        _externalLink = externalLink_;
    }

    function _setTokenImageURL(string memory tokenImageURL_) internal {
        _tokenImageURL = tokenImageURL_;
    }

    function _setTokenDescription(string memory tokenDescription_) internal {
        _tokenDescription = tokenDescription_;
    }

    function _setContractToBurn(address contractToBurn_) internal {
        CONTRACT_TO_BURN = contractToBurn_;
    }

    function _setQuantityToBurn(uint256 qtyToBurn_) internal {
        QTY_TO_BURN = qtyToBurn_;
    }

    /**
     * URIs
     */

    function contractURI() public view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "',
                                    name(),
                                    '", ',
                                    '"description": "',
                                    description(),
                                    '", ',
                                    '"external_link": "',
                                    externalLink(),
                                    '"}'
                                )
                            )
                        )
                    )
                )
            );
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "',
                                    name(),
                                    " ",
                                    Strings.toString(tokenId),
                                    '", ',
                                    '"description": "',
                                    tokenDescription(),
                                    '", ',
                                    '"image": "',
                                    tokenImageURL(),
                                    '"}'
                                )
                            )
                        )
                    )
                )
            );
    }

    /**
     * Mint
     */

    function mint(uint256 mintQuantity, uint256[] memory tokenIds) public {
        IContractToBurn burningContract = IContractToBurn(CONTRACT_TO_BURN);

        if (tokenIds.length != mintQuantity * QTY_TO_BURN) {
            revert InsufficientTokenstoBurn();
        }

        for (uint256 i = 0; i < tokenIds.length; ) {
            require(
                burningContract.ownerOf(tokenIds[i]) == msg.sender,
                string(
                    abi.encodePacked(
                        "Must own tokenId ",
                        Strings.toString(tokenIds[i])
                    )
                )
            );

            burningContract.burn(tokenIds[i]);

            unchecked {
                i++;
            }
        }

        super._mint(msg.sender, mintQuantity);
    }

    /**
     * Transfer/Permissions
     */

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public payable override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

