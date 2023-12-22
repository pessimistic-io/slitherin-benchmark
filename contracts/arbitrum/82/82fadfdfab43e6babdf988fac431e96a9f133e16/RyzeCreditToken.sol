// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./AccessControlEnumerable.sol";
import "./ERC1155.sol";
import "./ERC1155Burnable.sol";
import "./ERC1155Supply.sol";
import "./ERC1155URIStorage.sol";

/**
 * @title Free Credit Token
 * @author Balance Capital
 */
contract RyzeCreditToken is
    AccessControlEnumerable,
    ERC1155,
    ERC1155Burnable,
    ERC1155Supply,
    ERC1155URIStorage
{
    event CollectionAdded(uint256 indexed tokenId);
    event WhitelistEnabled();
    event WhitelistDisabled();
    event Whitelisted(address[] users, bool whitelisted);

    // Minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public nextTokenId;

    // enable/disable whitelisting
    bool public whitelistEnabled;
    // user => whitelisted
    mapping(address => bool) public whitelisted;

    constructor(string memory _uri) ERC1155(_uri) {
        _setBaseURI(_uri);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());

        // token ID starts from 1
        nextTokenId = 1;

        // Enable whitelist by default
        whitelistEnabled = true;
    }

    /// @notice Set the base URI
    /// @dev Only owner
    /// @param _uri The base URI
    function setBaseUri(string memory _uri)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setBaseURI(_uri);
    }

    /// @notice Set Token URI
    /// @dev Only owner
    /// @param _tokenId The token ID
    /// @param _tokenURI The token URI
    function setURI(uint256 _tokenId, string memory _tokenURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setURI(_tokenId, _tokenURI);
    }

    /// @notice Enable Whitelist
    /// @dev Only owner
    function enableWhitelist() external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistEnabled = true;
        emit WhitelistEnabled();
    }

    /// @notice Disable Whitelist
    /// @dev Only owner
    function disableWhitelist() external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistEnabled = false;
        emit WhitelistDisabled();
    }

    /// @notice Whitelist/Blacklist list of addresses
    /// @dev Only owner
    /// @param _users The list of users
    /// @param _whitelisted Whitelisted or not
    function whitelist(address[] memory _users, bool _whitelisted)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 i = 0; i < _users.length; ++i) {
            whitelisted[_users[i]] = _whitelisted;
        }
        emit Whitelisted(_users, _whitelisted);
    }

    /// @notice Add a new collection
    /// @dev Only owner
    function addCollection() external onlyRole(DEFAULT_ADMIN_ROLE) {
        nextTokenId++;
        emit CollectionAdded(nextTokenId);
    }

    /// @notice Mint free credit tokens
    /// @dev Only minter role
    /// @param _to The recipient address
    /// @param _tokenId The token ID
    /// @param _amount The token amount to mint
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyRole(MINTER_ROLE) {
        require(_tokenId > 0 && _tokenId < nextTokenId, "Invalid collection");

        _mint(_to, _tokenId, _amount, "0x");
    }

    /// @notice Mint free credit tokens
    /// @dev Only minter role
    /// @param _to The recipient address
    /// @param _tokenIds The token IDs
    /// @param _amounts The token amounts to mint
    function mintBatch(
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts
    ) external onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            require(
                _tokenIds[i] > 0 && _tokenIds[i] < nextTokenId,
                "Invalid collection"
            );
        }

        _mintBatch(_to, _tokenIds, _amounts, "0x");
    }

    /// @notice Returns the URI of token ID
    /// @param tokenId The token ID
    /// @return The URI of the token ID
    function uri(uint256 tokenId)
        public
        view
        override(ERC1155, ERC1155URIStorage)
        returns (string memory)
    {
        return ERC1155URIStorage.uri(tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlEnumerable, ERC1155)
        returns (bool)
    {
        return
            AccessControlEnumerable.supportsInterface(interfaceId) ||
            ERC1155.supportsInterface(interfaceId);
    }

    /// @notice Disable transfer
    function _beforeTokenTransfer(
        address, // operator,
        address from,
        address to,
        uint256[] memory, // ids,
        uint256[] memory, // amounts,
        bytes memory // data
    ) internal view override(ERC1155, ERC1155Supply) {
        // mint/burn or to whitelisted
        require(
            from == address(0) ||
                to == address(0) ||
                !whitelistEnabled ||
                whitelisted[to],
            "Cannot transfer"
        );
    }
}

