// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./ERC1155Pausable.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./VaultErrors.sol";

/**
 * @title SVS.sol
 * @author Souq.Finance
 * @notice Souq Vault Share (SVS) is a contract for managing NFT tranches.
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

contract SVS is ERC1155Pausable, Ownable {
    using Strings for uint256;

    string public name;
    string public symbol;
    string public baseURI;
    address vaultAddress;

    mapping(uint256 => uint256) public tokenTranche; //tokenID -> timestamp
    mapping(uint256 => uint256) public totalSupplyPerTranche; //tokenID -> totalSupply

    // Mapping from token ID to list of owners
    mapping(uint256 => address[]) public tokenOwners;
    // Mapping from token ID to address to index in the owners list
    mapping(uint256 => mapping(address => uint256)) private ownerIndexes;
    // Mapping from token ID to address to track if an address is an owner
    mapping(uint256 => mapping(address => bool)) private isTokenOwner;

    event vaultAddressSet(address vaultAddress);

    modifier onlyVault() {
        require(msg.sender == vaultAddress, VaultErrors.ONLY_VAULT);
        _;
    }

    constructor(string memory _baseURI) ERC1155("") {
        name = "Souq Vault Share";
        symbol = "SVS";
        baseURI = _baseURI;
    }

    /**
     * @dev Sets the base URI for SVS NFTs.
     * @param _newBaseURI The new base URI.
     */

    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
    }

    /**
     * @dev Gets the URI for a specific SVS token ID.
     * @param _id The SVS token ID.
     * @return The URI for the token.
     */

    function uri(uint256 _id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, _id.toString()));
    }

    /**
     * @dev Mints SVS tokens to an address.
     * @param _to The address to receive the tokens.
     * @param _id The SVS token ID.
     * @param _amount The amount of tokens to mint.
     * @param _data Additional data.
     */

    function mint(address _to, uint256 _id, uint256 _amount, bytes memory _data) external onlyVault {
        require(_to != address(0), VaultErrors.ADDRESS_IS_ZERO);
        totalSupplyPerTranche[_id] += _amount;
        _mint(_to, _id, _amount, _data);
        _addTokenOwner(_id, _to);
    }

    /**
     * @dev Burns SVS tokens from an address.
     * @param _account The address to burn tokens from.
     * @param _id The SVS token ID.
     * @param _amount The amount of tokens to burn.
     */

    function burn(address _account, uint256 _id, uint256 _amount) external onlyVault {
        require(_account != address(0), VaultErrors.ADDRESS_IS_ZERO);
        totalSupplyPerTranche[_id] -= _amount;
        _burn(_account, _id, _amount);
        if (balanceOf(_account, _id) == 0) {
            _removeTokenOwner(_id, _account);
        }
    }

    /**
     * @dev Sets timestamps for SVS tranches.
     * @param _baseTokenId The base token ID.
     * @param _timestamps The number of timestamps to set.
     */

    function setTokenTrancheTimestamps(uint256 _baseTokenId, uint256 _timestamps) external onlyVault {
        for (uint256 i = 0; i < _timestamps; ++i) {
            tokenTranche[_baseTokenId + i] = block.timestamp - (block.timestamp % 1 days);
        }
    }

    /**
     * @dev Sets the vault address.
     * @param _vaultAddress The new vault address.
     */
     
    function setVaultAddress(address _vaultAddress) external onlyOwner {
        require(_vaultAddress != address(0), VaultErrors.ADDRESS_IS_ZERO);
        vaultAddress = _vaultAddress;
        emit vaultAddressSet(_vaultAddress);
    }

    /**
     * @dev Transfers SVS tokens from one address to another, and updates token owner information.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param id The SVS token ID.
     * @param amount The amount of tokens to transfer.
     * @param data Additional data.
     */

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) public virtual override {
        require(to != address(0), VaultErrors.ADDRESS_IS_ZERO);
        super.safeTransferFrom(from, to, id, amount, data);
        // After the transfer, check and update the token owners list
        _afterTokenTransfer(from, to, id);
    }

    /**
     * @dev Transfers batches of SVS tokens from one address to another, and updates token owner information.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param ids The SVS token IDs.
     * @param amounts The amounts of tokens to transfer for each token ID.
     * @param data Additional data.
     */
     
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(to != address(0), VaultErrors.ADDRESS_IS_ZERO);
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
        // After the transfer, check and update the token owners list for each token ID
        for (uint256 i = 0; i < ids.length; ++i) {
            _afterTokenTransfer(from, to, ids[i]);
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 id) internal {
        if (balanceOf(from, id) == 0) {
            _removeTokenOwner(id, from);
        }

        if (balanceOf(to, id) > 0 && !isTokenOwner[id][to]) {
            _addTokenOwner(id, to);
        }
    }

    function _addTokenOwner(uint256 _tokenId, address _owner) internal {
        if (!isTokenOwner[_tokenId][_owner]) {
            tokenOwners[_tokenId].push(_owner);
            ownerIndexes[_tokenId][_owner] = tokenOwners[_tokenId].length - 1;
            isTokenOwner[_tokenId][_owner] = true;
        }
    }

    function _removeTokenOwner(uint256 _tokenId, address _owner) internal {
        if (isTokenOwner[_tokenId][_owner]) {
            uint256 lastIndex = tokenOwners[_tokenId].length - 1;
            address lastOwner = tokenOwners[_tokenId][lastIndex];

            // Move the last owner to the slot of the owner to delete
            tokenOwners[_tokenId][ownerIndexes[_tokenId][_owner]] = lastOwner;
            ownerIndexes[_tokenId][lastOwner] = ownerIndexes[_tokenId][_owner];

            // Delete the last owner from the array
            tokenOwners[_tokenId].pop();
            isTokenOwner[_tokenId][_owner] = false;
        }
    }
}

