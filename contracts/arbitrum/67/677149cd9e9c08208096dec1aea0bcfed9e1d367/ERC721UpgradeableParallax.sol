//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./AccessControlUpgradeable.sol";

import "./ERC721Upgradeable.sol";

import "./OwnableUpgradeable.sol";

contract ERC721UpgradeableParallax is
    AccessControlUpgradeable,
    ERC721Upgradeable
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     *  @notice Initializes the contract.
     *  @param name token name erc721
     *  @param symbol token symbol erc721
     */
    function __ERC721UpgradeableParallax__init(
        string memory name,
        string memory symbol
    ) external initializer {
        __ERC721_init_unchained(name, symbol);
        __ERC721UpgradeableParallax_init_unchained();
    }

    /**
     *  @notice Mints `tokenId` and transfers it to `to`.
     *  @param to recipient of the token
     *  @param tokenId ID of the token
     */
    function mint(
        address to,
        uint256 tokenId
    ) external onlyRole(OPERATOR_ROLE) {
        _mint(to, tokenId);
    }

    /**
     *  @dev Destroys `tokenId`. For owner or by approval to transfer.
     *       The approval is cleared when the token is burned.
     *  @param tokenId ID of the token
     */
    function burn(uint256 tokenId) external onlyRole(OPERATOR_ROLE) {
        _burn(tokenId);
    }

    /// @inheritdoc ERC721Upgradeable
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyRole(OPERATOR_ROLE) {
        _transfer(from, to, tokenId);
    }

    /// @inheritdoc ERC721Upgradeable
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyRole(OPERATOR_ROLE) {
        _safeTransfer(from, to, tokenId, "");
    }

    /// @inheritdoc ERC721Upgradeable
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override onlyRole(OPERATOR_ROLE) {
        _safeTransfer(from, to, tokenId, data);
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function __ERC721UpgradeableParallax_init_unchained()
        internal
        onlyInitializing
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }
}

