// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./ERC721.sol";

contract OnChainCredential is ERC721 {
    error InvalidMintAuthority();
    error TransferNotAllowed();
    error InvalidCaller();

    mapping(uint256 => string) private metadata;
    address internal mint_authority;
    address public owner;
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

    /// @notice Mints NFT Credential
    /// @dev Explain to a developer any extra details
    /// @param token_metadata Metadata of the token
    /// @param to Address of the receiver
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
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(from, to, id);
    }

    /// @notice Updates the mint authority
    /// @param newAuthority Address of the new mint authority
    function updateMintAuthority(address newAuthority) external {
        if (msg.sender != owner) revert InvalidCaller();
        mint_authority = newAuthority;
    }
}

