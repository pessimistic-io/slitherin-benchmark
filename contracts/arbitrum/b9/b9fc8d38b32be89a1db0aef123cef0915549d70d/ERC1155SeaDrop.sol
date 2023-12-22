// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {     ERC1155ContractMetadata,     ISeaDrop1155TokenContractMetadata } from "./ERC1155ContractMetadata.sol";

import {     INonFungibleSeaDrop1155Token } from "./INonFungibleSeaDrop1155Token.sol";

import { ISeaDrop1155 } from "./ISeaDrop1155.sol";

import {     PublicDrop,     PrivateDrop,     WhiteList,     MultiConfigure,     MintStats } from "./SeaDrop1155Structs.sol";

import {     ERC1155SeaDropStructsErrorsAndEvents } from "./ERC1155SeaDropStructsErrorsAndEvents.sol";

import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import {     IERC165 } from "./IERC165.sol";

import {     DefaultOperatorFilterer } from "./DefaultOperatorFilterer.sol";

/**
 * @title  ERC721SeaDrop
 * @author James Wenzel (emo.eth)
 * @author Ryan Ghods (ralxz.eth)
 * @author Stephan Min (stephanm.eth)
 * @author Michael Cohen (notmichael.eth)
 * @notice ERC721SeaDrop is a token contract that contains methods
 *         to properly interact with SeaDrop.
 */
contract ERC1155SeaDrop is
    ERC1155ContractMetadata,
    INonFungibleSeaDrop1155Token,
    ERC1155SeaDropStructsErrorsAndEvents,
    ReentrancyGuard,
    DefaultOperatorFilterer
{
    /// @notice Track the allowed SeaDrop addresses.
    mapping(address => bool) internal _allowedSeaDrop;

    /// @notice Track the enumerated allowed SeaDrop addresses.
    address[] internal _enumeratedAllowedSeaDrop;

    /// @notice Track the total minted.
    uint256 private _totalMinted;

    /**
     * @dev Reverts if not an allowed SeaDrop contract.
     *      This function is inlined instead of being a modifier
     *      to save contract space from being inlined N times.
     *
     * @param seaDrop The SeaDrop address to check if allowed.
     */
    function _onlyAllowedSeaDrop(address seaDrop) internal view {
        if (_allowedSeaDrop[seaDrop] != true) {
            revert OnlyAllowedSeaDrop();
        }
    }

    /**
     * @notice Deploy the token contract with its uri,
     *         and allowed SeaDrop addresses.
     */
    constructor(
        string memory _uri,
        address[] memory allowedSeaDrop
    ) ERC1155ContractMetadata(_uri) {
        // Put the length on the stack for more efficient access.
        uint256 allowedSeaDropLength = allowedSeaDrop.length;

        // Set the mapping for allowed SeaDrop contracts.
        for (uint256 i = 0; i < allowedSeaDropLength; ) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Set the enumeration.
        _enumeratedAllowedSeaDrop = allowedSeaDrop;

        // Emit an event noting the contract deployment.
        emit SeaDropTokenDeployed();
    }

    /**
     * @notice Update the allowed SeaDrop contracts.
     *         Only the owner or administrator can use this function.
     *
     * @param allowedSeaDrop The allowed SeaDrop addresses.
     */
    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop)
        external
        virtual
        override
        onlyOwner
    {
        _updateAllowedSeaDrop(allowedSeaDrop);
    }

    /**
     * @notice Internal function to update the allowed SeaDrop contracts.
     *
     * @param allowedSeaDrop The allowed SeaDrop addresses.
     */
    function _updateAllowedSeaDrop(address[] calldata allowedSeaDrop) internal {
        // Put the length on the stack for more efficient access.
        uint256 enumeratedAllowedSeaDropLength = _enumeratedAllowedSeaDrop
            .length;
        uint256 allowedSeaDropLength = allowedSeaDrop.length;

        // Reset the old mapping.
        for (uint256 i = 0; i < enumeratedAllowedSeaDropLength; ) {
            _allowedSeaDrop[_enumeratedAllowedSeaDrop[i]] = false;
            unchecked {
                ++i;
            }
        }

        // Set the new mapping for allowed SeaDrop contracts.
        for (uint256 i = 0; i < allowedSeaDropLength; ) {
            _allowedSeaDrop[allowedSeaDrop[i]] = true;
            unchecked {
                ++i;
            }
        }

        // Set the enumeration.
        _enumeratedAllowedSeaDrop = allowedSeaDrop;

        // Emit an event for the update.
        emit AllowedSeaDropUpdated(allowedSeaDrop);
    }

    

    /**
     * @notice Mint tokens, restricted to the SeaDrop contract.
     *
     * @dev    NOTE: If a token registers itself with multiple SeaDrop
     *         contracts, the implementation of this function should guard
     *         against reentrancy. If the implementing token uses
     *         _safeMint(), or a feeRecipient with a malicious receive() hook
     *         is specified, the token or fee recipients may be able to execute
     *         another mint in the same transaction via a separate SeaDrop
     *         contract.
     *         This is dangerous if an implementing token does not correctly
     *         update the minterNumMinted and currentTotalSupply values before
     *         transferring minted tokens, as SeaDrop references these values
     *         to enforce token limits on a per-wallet and per-stage basis.
     *
     *         ERC721A tracks these values automatically, but this note and
     *         nonReentrant modifier are left here to encourage best-practices
     *         when referencing this contract.
     *
     * @param minter   The address to mint to.
     * @param tokenId The Id of tokens to mint.
     * @param quantity The number of tokens to mint.
     */
    function mintSeaDrop(address minter, uint256 tokenId, uint256 quantity)
        external
        virtual
        override
        nonReentrant
    {
        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(msg.sender);

        // Extra safety check to ensure the max supply is not exceeded.
        if (_totalMinted + quantity > maxSupply()) {
            revert MintQuantityExceedsMaxSupply(
                _totalMinted + quantity,
                maxSupply()
            );
        }

        // Mint the quantity of tokens to the minter.
        _mint(minter, tokenId, quantity, "");

        _totalMinted += quantity;
    }

    /**
     * @notice Update the public drop data for this nft contract on SeaDrop.
     *         Only the owner can use this function.
     *
     * @param seaDropImpl The allowed SeaDrop contract.
     * @param publicDrop  The public drop data.
     */
    function updatePublicDrop(
        address seaDropImpl,
        PublicDrop calldata publicDrop
    ) external virtual override {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(seaDropImpl);

        // Update the public drop data on SeaDrop.
        ISeaDrop1155(seaDropImpl).updatePublicDrop(publicDrop);
    }

    /**
     * @notice Update the private drop data for this nft contract on SeaDrop.
     *         Only the owner can use this function.
     *
     * @param seaDropImpl   The allowed SeaDrop contract.
     * @param privateDrop The private drop datas.
     */
    function updatePrivateDrop(
        address seaDropImpl,
        PrivateDrop calldata privateDrop
    ) external virtual override {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(seaDropImpl);

        // Update the private drop on SeaDrop.
        ISeaDrop1155(seaDropImpl).updatePrivateDrop(privateDrop);
    }

    /**
     * @notice Update the white list data for this nft contract on SeaDrop.
     *         Only the owner can use this function.
     *
     * @param seaDropImpl   The allowed SeaDrop contract.
     * @param whiteList       The white list datas.
     */
    function updateWhiteList(
        address seaDropImpl,
        WhiteList calldata whiteList
    ) external virtual override {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(seaDropImpl);

        // Update the white list on SeaDrop.
        ISeaDrop1155(seaDropImpl).updateWhiteList(whiteList);
    }

    /**
     * @notice Update the creator payout address for this nft contract on
     *         SeaDrop.
     *         Only the owner can set the creator payout address.
     *
     * @param seaDropImpl   The allowed SeaDrop contract.
     * @param payoutAddress The new payout address.
     */
    function updateCreatorPayoutAddress(
        address seaDropImpl,
        address payoutAddress
    ) external override {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(seaDropImpl);

        // Update the creator payout address.
        ISeaDrop1155(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    /**
     * @notice Update the signer address for this nft contract on SeaDrop.
     *         Only the owner can set the signer address.
     *
     * @param seaDropImpl The allowed SeaDrop contract.
     * @param signer      The new signer address.
     */
    function updateSigner(
        address seaDropImpl,
        address signer
    ) external override {
        // Ensure the sender is only the owner or contract itself.
        _onlyOwnerOrSelf();

        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(seaDropImpl);

        // Update the signer address.
        ISeaDrop1155(seaDropImpl).updateSigner(signer);
    }

    /**
     * @notice Returns whether the interface is supported.
     *
     * @param interfaceId The interface id to check against.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC1155ContractMetadata)
        returns (bool)
    {
        return
            interfaceId == type(INonFungibleSeaDrop1155Token).interfaceId ||
            interfaceId == type(ISeaDrop1155TokenContractMetadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom}
     * for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     * - The `operator` must be allowed.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @notice Configure multiple properties at a time.
     *
     *         Note: The individual configure methods should be used
     *         to unset or reset any properties to zero, as this method
     *         will ignore zero-value properties in the config struct.
     *
     * @param config The configuration struct.
     */
    function multiConfigure(MultiConfigure calldata config)
        external
        onlyOwner
    {
        if (config.maxSupply > 0) {
            this.setMaxSupply(config.maxSupply);
        }
        if (_cast(config.whiteList.startTime != 0) |
                _cast(config.whiteList.endTime != 0) ==
            1
        ) {
            this.updateWhiteList(config.seaDropImpl, config.whiteList);
        }
        if (_cast(config.privateDrop.startTime != 0) |
                _cast(config.privateDrop.endTime != 0) ==
            1
        ) {
            this.updatePrivateDrop(config.seaDropImpl, config.privateDrop);
        }
        if (
            _cast(config.publicDrop.startTime != 0) |
                _cast(config.publicDrop.endTime != 0) ==
            1
        ) {
            this.updatePublicDrop(config.seaDropImpl, config.publicDrop);
        }
        
        if (config.creatorPayoutAddress != address(0)) {
            this.updateCreatorPayoutAddress(
                config.seaDropImpl,
                config.creatorPayoutAddress
            );
        }
        if (config.signer != address(0)) {
            this.updateSigner(
                config.seaDropImpl,
                config.signer
            );
        }
    }

    /**
     * @notice get mint stats
     */
    function getMintStats()  public view override returns (MintStats memory) {
        return MintStats(maxSupply(), _totalMinted);
    }

    /**
     * @notice sweep nft
     * @param minter The minter address.
     * @param tokenId The token id.
     * @param quantity The quantity to mint.
     */
    function sweepNFT(
        address minter, 
        uint256 tokenId,
        uint256 quantity
    ) external onlyOwner nonReentrant {
        // Extra safety check to ensure the max supply is not exceeded.
        if (_totalMinted + quantity > maxSupply()) {
            revert MintQuantityExceedsMaxSupply(
                _totalMinted + quantity,
                maxSupply()
            );
        }

        // Mint the quantity of tokens to the minter.
        _mint(minter, tokenId, quantity, "");

        _totalMinted += quantity;

        emit SweepNFT(minter, quantity);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
    
}

