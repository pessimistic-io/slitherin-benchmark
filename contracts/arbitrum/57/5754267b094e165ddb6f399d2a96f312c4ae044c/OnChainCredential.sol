// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @author devfolio

import "./ERC721.sol";

/// @title The OnChainCredential NFT Contract
/// @author devfolio
/// @notice The ERC721 contract for the OnChainCredential NFT Contract
contract OnChainCredential is ERC721 {
    /// @dev The Error thrown when the mint authority is not the caller
    error InvalidMintAuthority();
    /// @dev The Error thrown when the caller is not allowed to transfer the token
    error TransferNotAllowed();
    /// @dev The Error thrown when the caller is not the owner
    error InvalidCaller();

    /// @dev mapping of the tokenId to the metadata
    mapping(uint256 => string) private metadata;
    /// @dev The addrerss of the mint authority that is allowed to mint the NFT
    address internal mint_authority;
    /// @notice The owner of the contract
    address public owner;
    /// @dev The current token ID index
    uint256 tokenIDs = 0;

    constructor(
        string memory name,
        string memory symbol,
        address _mint_authority,
        address _owner
    ) ERC721(name, symbol) {
        mint_authority = _mint_authority;
        owner = _owner;
    }

    /// @notice Mints the OnChainCredential NFT
    /// @dev Only the mint authority can mint the NFT
    /// @param token_metadata Metadata of the token
    /// @param to Address of the receiver of the NFT
    function mint(string calldata token_metadata, address to) external {
        if (msg.sender != mint_authority) revert InvalidMintAuthority();

        uint256 current_token_index = tokenIDs;
        metadata[current_token_index] = token_metadata;

        _mint(to, current_token_index);

        unchecked {
            tokenIDs++;
        }
    }

    /// @notice Returns the metadata of the token
    /// @param id ID of the token
    /// @return Documents the return variables of a contract’s function state variable
    function tokenURI(
        uint256 id
    ) public view virtual override returns (string memory) {
        return metadata[id];
    }

    /// @notice Internal Transfer Function
    /// @param from address of current owner
    /// @param to address of new owner
    /// @param id ID of the token
    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual override {
        if (msg.sender != owner) revert TransferNotAllowed();

        /// @dev Reference:
        /// https://github.com/transmissions11/solmate/blob/bfc9c25865a274a7827fea5abf6e4fb64fc64e6c/src/tokens/ERC721.sol#L82
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(from, to, id);
    }

    /// @notice Updates the mint authority of the OnChainCredential Contract
    /// @param newAuthority Address of the new mint authority
    function updateMintAuthority(address newAuthority) external {
        if (msg.sender != owner) revert InvalidCaller();
        mint_authority = newAuthority;
    }
}

