// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import "./ERC721A.sol";
import {IERC4906} from "./IERC4906.sol";
import {ILayerr721A} from "./ILayerr721A.sol";
import {ILayerrRenderer} from "./ILayerrRenderer.sol";
import {LayerrToken} from "./LayerrToken.sol";
import "./DefaultOperatorFilterer.sol";

/**
 * @title Layerr721A
 * @author 0xth0mas (Layerr)
 * @notice Layerr721A is an ERC721 contract built for the Layerr platform using
 *         the Chiru Labs ERC721A implementation for gas efficient sequential 
 *         minting.
 */
contract Layerr721A is DefaultOperatorFilterer, ERC721A, ILayerr721A, LayerrToken, IERC4906 {

    /** METADATA FUNCTIONS */

    /**
     * @notice Returns the URI for a given `tokenId`
     * @param tokenId id of token to return URI of
     * @return tokenURI location of the token metadata
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return ILayerrRenderer(_getRenderer()).tokenURI(address(this), tokenId);
    }

    /**
     * @notice Returns the URI for the contract metadata
     * @return contractURI location of the contract metadata
     */
    function contractURI() public view returns (string memory) {
        return ILayerrRenderer(_getRenderer()).contractURI(address(this));
    }

    /**
     * @inheritdoc LayerrToken
     */
    function name() public view virtual override(LayerrToken, ERC721A) returns (string memory) {
        return LayerrToken.name();
    }

    /**
     * @inheritdoc LayerrToken
     */
    function symbol() public view virtual override(LayerrToken, ERC721A) returns (string memory) {
        return LayerrToken.symbol();
    }

    /** MINT FUNCTIONS */

    /**
     * @inheritdoc ILayerr721A
     */
    function mintSequential(address minter, address to, uint256 quantity) external onlyMinter {
        _mint(minter, to, quantity);
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function burnTokenId(address from, uint256 tokenId) external {
        if (!isApprovedForAll(from, msg.sender)) {
            revert NotAuthorized();
        }
        if(ownerOf(tokenId) != from) { revert NotAuthorized(); }
        _burn(tokenId, true);
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function burnBatchTokenIds(
        address from,
        uint256[] calldata tokenIds
    ) external {
        if (!isApprovedForAll(from, msg.sender)) {
            revert NotAuthorized();
        }
        for(uint256 i = 0;i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];

            if(ownerOf(tokenId) != from) { revert NotAuthorized(); }
            _burn(tokenId, true);

            unchecked { ++i; }
        }
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function totalSupply() public view override(ERC721A, ILayerr721A) returns (uint256) {
        return ERC721A.totalSupply();
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function totalMintedCollectionAndMinter(address minter) external view returns(uint256 totalMinted, uint256 minterMinted) {
        totalMinted = _totalMinted();
        minterMinted = _numberMinted(minter);
    }

    /** OWNER FUNCTIONS */

    /**
     * @inheritdoc ILayerr721A
     */
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        if(recipients.length != amounts.length) { revert ArrayLengthMismatch(); }

        for(uint256 index = 0;index < recipients.length;) {
            _mint(msg.sender, recipients[index], amounts[index]);

            unchecked { ++index; }
        }
    }

    /**
     * @notice Subscribes to an operator filter registry
     * @param operatorFilterRegistry operator filter address to subscribe to
     */
    function setOperatorFilter(address operatorFilterRegistry) external onlyOwner {
        if (operatorFilterRegistry != address(0)) {
            OPERATOR_FILTER_REGISTRY.registerAndSubscribe(
                address(this),
                operatorFilterRegistry
            );
        }
    }

    /**
     * @notice Unsubscribes from the operator filter registry
     */
    function removeOperatorFilter() external onlyOwner {
        OPERATOR_FILTER_REGISTRY.unregister(
            address(this)
        );
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function updateMetadataAllTokens() external onlyOwner {
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /**
     * @inheritdoc ILayerr721A
     */
    function updateMetadataSpecificTokens(uint256[] calldata tokenIds) external onlyOwner {
        for(uint256 i; i < tokenIds.length; ) {
            emit MetadataUpdate(tokenIds[i]);

            unchecked { ++i; }
        }
    }

    /** OPERATOR FILTER OVERRIDES */

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

    /** ERC165 */

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(LayerrToken, ERC721A) returns (bool) {
        return
            interfaceId == type(ILayerr721A).interfaceId ||
            LayerrToken.supportsInterface(interfaceId) ||
            ERC721A.supportsInterface(interfaceId);
    }
}

