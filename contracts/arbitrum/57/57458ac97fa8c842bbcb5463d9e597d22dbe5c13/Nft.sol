// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./Context.sol";
import "./IERC721Receiver.sol";
import "./ERC165.sol";
import "./Strings.sol";
import "./Address.sol";

import "./INftStorage.sol";
import "./IBalance.sol";

/**
 * @dev Storageless ERC721 implementation based on @openzeppelin/contracts/token/ERC721/ERC721.sol
 */
abstract contract Nft is Context, IBalance, INftStorage, ERC165, IERC721, IERC721Metadata {
    /**
     * @dev Wrong NFT state.
     */
    error WrongNftState(uint tokenId, StateType expected, StateType got);
    /**
     * @dev NFT wasn't properly locked.
     */
    error NftMustBeLocked(uint tokenId);

    /**
     * @dev The NFT is locked, and no operations can be performed with it in this state.
     */
    error NftIsLocked(uint tokenId);

    using StateTypeLib for uint256;
    using StateTypeLib for StateType;
    using Strings for uint256;
    using IdTypeLib for uint256;
    using IdTypeLib for IdType;
    using Address for address;

    event Locked(uint tokenId);
    event Unlocked(uint tokenId);
    event MetadataUpdate(uint tokenId);

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _getTotalNftCount(owner);
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _nft(tokenId.toId()).owner;
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name();
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol();
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        IdType id = tokenId.toId();
        NFTDef storage nft = _nft(id);
        require(nft.owner != address(0), "ERC721: invalid token ID");
        bool isLocked = nft.flags & NFT_FLAG_LOCKED != 0;

        string memory baseURI = _baseURI();
        StateType nftState = nft.state;
        if (nftState.isMystery()) {
            return string(abi.encodePacked(baseURI, "mystic.json"));
        }
        else if (nftState.isEmpty()) {
            return string(abi.encodePacked(baseURI, "empty", isLocked ? "_locked.json" : ".json"));
        }
        else if (nftState.isRare()) {
            uint rarity = nftState.toRarity();
            return string(abi.encodePacked(baseURI, "rarity", rarity.toString(), isLocked ? "_locked.json" : ".json"));
        }

        revert("ERC721: invalid token state");
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = Nft.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner or approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

        return _nft(tokenId.toId()).approval;
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals(owner, operator);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return _nft(tokenId.toId()).owner;
    }

    /**
     * @dev Returns the owner of the `id`. Does NOT revert if token doesn't exist
     */
    function _ownerOf(IdType id) internal view virtual returns (address) {
        return _nft(id).owner;
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns whether a token with the specified `id` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(IdType id) internal view virtual returns (bool) {
        return _ownerOf(id) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        address owner = Nft.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, IdType id, uint16 boost) internal virtual {
        _safeMint(to, id, boost, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, IdType id, uint16 boost, bytes memory data) internal virtual {
        _mint(to, id, boost);
        require(
            _checkOnERC721Received(address(0), to, id.toTokenId(), data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     * Emits {Transfer} and {Locked} events.
     */
    function _mint(address to, IdType id, uint16 boost) internal virtual {
        NFTDef storage nft = _nft(id);

        nft.owner = to;
        nft.state = MYSTERY_STATE;
        nft.flags = NFT_FLAG_LOCKED;
        nft.boost = boost;

        _insertNft(to, id, nft);

        uint tokenId = id.toTokenId();
        emit Transfer(address(0), to, tokenId);
        emit Locked(tokenId);
    }

    /**
     * @dev Updates status to Empty for the specified token.
     * Emits a {Unlocked} event.
     */
    function _markAsEmpty(IdType id, uint32 random) internal {
        NFTDef storage nft = _nft(id);
        if (nft.state.isNotMystery()) {
            revert WrongNftState(id.toTokenId(), nft.state, MYSTERY_STATE);
        }

        // remove mystery nft
        _removeNft(nft.owner, nft);

        // change nft type
        nft.state = EMPTY_STATE;
        nft.entropy = random;

        _unlockAndReturn(id, nft);
    }

    /**
     * @dev Updates rarity and entropy of the specified token.
     * Emits a {Unlocked} event.
     */
    function _markAsRare(IdType id, uint rarityLevel, uint32 random) internal {
        NFTDef storage nft = _nft(id);
        if (nft.state.isNotMystery()) {
            revert WrongNftState(id.toTokenId(), nft.state, MYSTERY_STATE);
        }

        // remove mystery nft from the user
        _removeNft(nft.owner, nft);

        // change nft state
        nft.state = rarityLevel.toState();
        nft.entropy = random;

        _unlockAndReturn(id, nft);
    }

    /**
     * @dev Destroys first token by `rarity`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     *
     * - `nftState` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burnByRarity(address owner, uint rarity) internal virtual returns (IdType) {
        IdType id = _getHeadId(owner, rarity.toState());
        NFTDef storage nft = _nft(id);
        // remove an NFT from the user balance
        _removeNft(owner, nft);
        // delete an NFT definition completely
        _deleteNft(id);

        emit Transfer(owner, address(0), id.toTokenId());

        return id;
    }

    function _burnByRarityMultiple(address owner, uint rarity, uint32 count) internal virtual {
        for (uint i = 0; i < count; i ++) {
            _burnByRarity(owner, rarity);
        }
    }

    function _burnEmpty(address owner) private {
        IdType id = _getHeadId(owner, EMPTY_STATE);
        NFTDef storage nft = _nft(id);
        // remove an NFT from the user balance
        _removeNft(owner, nft);
        // delete an NFT definition completely
        _deleteNft(id);

        emit Transfer(owner, address(0), id.toTokenId());
    }

    function _burnEmptyMultiple(address owner, uint32 count) internal virtual {
        for (uint i = 0; i < count; i ++) {
            _burnEmpty(owner);
        }
    }

    function _lockFirst(address owner, uint rarity) internal virtual returns (IdType) {
        // check owner balance
        StateType nftState = rarity.toState();
        IdType id = _getHeadId(owner, nftState);
        NFTDef storage nft = _nft(id);
        _removeNft(owner, nft);
        nft.flags |= NFT_FLAG_LOCKED;

        emit Locked(id.toTokenId());

        return id;
    }

    function _unlockAndReturn(IdType id, NFTDef storage nft) internal virtual {
        if ((nft.flags & NFT_FLAG_LOCKED) == 0) {
            revert NftMustBeLocked(id.toTokenId());
        }
        // return a NFT on to the user balance
        _insertNft(nft.owner, id, nft);
        // and unlock it
        nft.flags &= ~NFT_FLAG_LOCKED;
        emit Unlocked(id.toTokenId());
        emit MetadataUpdate(id.toTokenId());
    }

    function _burnLocked(address owner, IdType id, NFTDef storage nft) internal virtual {
        if ((nft.flags & NFT_FLAG_LOCKED) == 0) {
            revert NftMustBeLocked(id.toTokenId());
        }

        _deleteNft(id);
        emit Transfer(owner, address(0), id.toTokenId());
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(Nft.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        IdType id = tokenId.toId();
        NFTDef storage nft = _nft(id);

        // check if nft is locked
        if (nft.flags & NFT_FLAG_LOCKED != 0) {
            revert NftIsLocked(tokenId);
        }

        _removeNft(from, nft);
        nft.owner = to;
        // Clear approvals from the previous owner
        nft.approval = address(0);
        _insertNft(to, id, nft);

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, id, 1);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _nft(tokenId.toId()).approval = to;
        emit Approval(Nft.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals(owner, operator, approved);
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (!to.isContract()) {
            return true;
        }

        try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        }
        catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("ERC721: transfer to non ERC721Receiver implementer");
            } else {
                /// @solidity memory-safe-assembly
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    /**
     * @dev Hook that is called after any token transfer. This includes minting and burning. If {ERC721Consecutive} is
     * used, the hook may be called as part of a consecutive (batch) mint, as indicated by `batchSize` greater than 1.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s tokens were transferred to `to`.
     * - When `from` is zero, the tokens were minted for `to`.
     * - When `to` is zero, ``from``'s tokens were burned.
     * - `from` and `to` are never both zero.
     * - `batchSize` is non-zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(address from, address to, IdType firstTokenId, uint256 batchSize) internal virtual {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}

