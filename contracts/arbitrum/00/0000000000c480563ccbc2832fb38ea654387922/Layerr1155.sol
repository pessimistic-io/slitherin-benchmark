// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import {ERC1155PSupply} from "./ERC1155PSupply.sol";
import {ILayerr1155} from "./ILayerr1155.sol";
import {ILayerrRenderer} from "./ILayerrRenderer.sol";
import {LayerrToken} from "./LayerrToken.sol";
import "./DefaultOperatorFilterer.sol";

/**
 * @title Layerr1155
 * @author 0xth0mas (Layerr)
 * @notice Layerr1155 is an ERC1155 contract built for the Layerr platform using
 *         the ERC1155P implementation for gas efficient mints, burns, purchases,  
 *         and transfers of multiple tokens.
 */
contract Layerr1155 is
    DefaultOperatorFilterer,
    ERC1155PSupply,
    ILayerr1155,
    LayerrToken
{

    /** METADATA FUNCTIONS */

    /**
     * @notice Returns the URI for a given `tokenId`
     * @param id id of token to return URI of
     * @return tokenURI location of the token metadata
     */
    function uri(
        uint256 id
    ) public view virtual override returns (string memory) {
        return ILayerrRenderer(_getRenderer()).tokenURI(address(this), id);
    }

    /**
     * @notice Returns the URI for the contract metadata
     * @return contractURI location of the contract metadata
     */
    function contractURI() public view returns (string memory) {
        return ILayerrRenderer(_getRenderer()).contractURI(address(this));
    }

    /** MINT FUNCTIONS */

    /**
     * @inheritdoc ILayerr1155
     */
    function mintTokenId(
        address minter,
        address to,
        uint256 id,
        uint256 amount
    ) external onlyMinter {
        _mint(minter, to, id, amount, "");
    }

    /**
     * @inheritdoc ILayerr1155
     */
    function mintBatchTokenIds(
        address minter,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyMinter {
        _mintBatch(minter, to, ids, amounts, "");
    }

    /**
     * @inheritdoc ILayerr1155
     */
    function burnTokenId(
        address from,
        uint256 tokenId,
        uint256 amount
    ) external {
        if (!isApprovedForAll(from, msg.sender)) {
            revert NotAuthorized();
        }
        _burn(from, tokenId, amount);
    }

    /**
     * @inheritdoc ILayerr1155
     */
    function burnBatchTokenIds(
        address from,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts
    ) external {
        if (!isApprovedForAll(from, msg.sender)) {
            revert NotAuthorized();
        }
        _burnBatch(from, tokenIds, amounts);
    }

    /**
     * @inheritdoc ILayerr1155
     */
    function totalSupply(uint256 id) public view override(ERC1155PSupply, ILayerr1155) returns (uint256) {
        return ERC1155PSupply.totalSupply(id);
    }
    
    /**
     * @inheritdoc ILayerr1155
     */
    function totalMintedCollectionAndMinter(address minter, uint256 id) external view returns(uint256 totalMinted, uint256 minterMinted) {
        totalMinted = totalSupply(id);
        minterMinted = _numberMinted(minter, id);
    }
    
    /** OWNER FUNCTIONS */

    /**
     * @inheritdoc ILayerr1155
     */
    function airdrop(address[] calldata recipients, uint256[] calldata tokenIds, uint256[] calldata amounts) external onlyOwner {
        if(recipients.length != tokenIds.length || tokenIds.length != amounts.length) { revert ArrayLengthMismatch(); }

        for(uint256 index = 0;index < recipients.length;) {
            _mint(msg.sender, recipients[index], tokenIds[index], amounts[index], "");

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
     * @inheritdoc ILayerr1155
     */
    function updateMetadataSpecificTokens(uint256[] calldata tokenIds) external onlyOwner {
        ILayerrRenderer renderer = ILayerrRenderer(_getRenderer());
        for(uint256 i; i < tokenIds.length; ) {
            uint256 tokenId = tokenIds[i];
            emit URI(renderer.tokenURI(address(this), tokenId), tokenId);
            
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

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes memory data
    ) public virtual override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    /** ERC165 */

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(LayerrToken, ERC1155PSupply) returns (bool) {
        return
            interfaceId == type(ILayerr1155).interfaceId ||
            LayerrToken.supportsInterface(interfaceId) ||
            ERC1155PSupply.supportsInterface(interfaceId);
    }
}

