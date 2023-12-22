// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

/// @author thirdweb

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

//  ==========  External imports    ==========

import "./StringsUpgradeable.sol";
import "./IERC2981Upgradeable.sol";

import "./ERC721EnumerableUpgradeable.sol";

//  ==========  Internal imports    ==========

import "./CurrencyTransferLib.sol";

//  ==========  Features    ==========

import "./Multicall.sol";
import "./ContractMetadata.sol";
import "./RoyaltyMigration.sol";
import "./PrimarySale.sol";
import "./Ownable.sol";
import "./SharedMetadata.sol";
import "./PermissionsEnumerable.sol";
import "./Drop.sol";

import "./TokenMigrateERC721.sol";

contract OpenEditionERC721M is
    Initializable,
    ContractMetadata,
    RoyaltyMigration,
    PrimarySale,
    Ownable,
    SharedMetadata,
    PermissionsEnumerable,
    Drop,
    Multicall,
    ERC721EnumerableUpgradeable,
    TokenMigrateERC721
{
    using StringsUpgradeable for uint256;

    /// @dev Unable to transfer the token due to missing role
    error OpenEditionTransferRestricted(address from, address to);

    /// @dev Invalid msg.value
    error OpenEditionInvalidMsgValue(uint256 expected, uint256 actual);

    /// @dev Non-existent token id
    error OpenEditionInvalidTokenId();

    /// @dev token owner or approved
    error OpenEditionNotApprovedOrOwner(address sender, uint256 tokenId);

    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    /// @dev Only transfers to or from TRANSFER_ROLE holders are valid, when transfers are restricted.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can update the shared metadata of tokens.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Only MIGRATION_ROLE holders for setting migration merkle root
    bytes32 private constant MIGRATION_ROLE = keccak256("MIGRATION_ROLE");

    /// @dev Next tokenId to be claimed.
    uint256 public nextTokenIdToClaim;

    /// @dev Next tokenId that was to be claimed on original contract.
    uint256 private migratedNextTokenId;

    /// @dev Max bps in the thirdweb system.
    uint256 private constant MAX_BPS = 10_000;

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

    constructor() initializer {}

    /// @dev Initializes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        address __originalContract,
        bytes32 _ownershipMerkleRoot,
        string memory _contractURI
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ERC721_init(OpenEditionERC721M(__originalContract).name(), OpenEditionERC721M(__originalContract).symbol());

        _setupOriginalContract(__originalContract);
        _setupMerkleRoot(_ownershipMerkleRoot);

        {
            (
                string memory _name,
                string memory _description,
                string memory _imageURI,
                string memory _animationURI
            ) = OpenEditionERC721M(__originalContract).sharedMetadata();

            sharedMetadata = SharedMetadataInfo({
                name: _name,
                description: _description,
                imageURI: _imageURI,
                animationURI: _animationURI
            });
        }

        {
            uint256 _nextIdToClaim = OpenEditionERC721M(__originalContract).nextTokenIdToClaim();
            nextTokenIdToClaim = _nextIdToClaim;
            migratedNextTokenId = _nextIdToClaim;

            (address royaltyRecipient, uint16 royaltyBps) = OpenEditionERC721M(__originalContract)
                .getDefaultRoyaltyInfo();
            address primarySaleRecipient = OpenEditionERC721M(__originalContract).primarySaleRecipient();

            if (royaltyRecipient != address(0)) {
                _setupDefaultRoyaltyInfo(royaltyRecipient, royaltyBps);
            }

            if (primarySaleRecipient != address(0)) {
                _setupPrimarySaleRecipient(primarySaleRecipient);
            }
        }

        _setupContractURI(_contractURI);
        _setupOwner(_defaultAdmin);

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);

        _setupRole(TRANSFER_ROLE, address(0));

        _setupRole(MIGRATION_ROLE, _defaultAdmin);
        _setRoleAdmin(MIGRATION_ROLE, MIGRATION_ROLE);
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        // Any minted tokens should exists. Migrated tokens that are unclaimed are valid too.
        // If a token doesn't exist but has been claimed = migrated and burned
        // If a token doesn't exist and tokenId is greater than migratedNextTokenId = new future invalid token
        if (!_exists(_tokenId) && (isOwnershipClaimed(_tokenId) || _tokenId >= migratedNextTokenId)) {
            revert OpenEditionInvalidTokenId();
        }

        return _getURIFromSharedMetadata(_tokenId);
    }

    /// @dev See ERC 165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721EnumerableUpgradeable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || type(IERC2981Upgradeable).interfaceId == interfaceId;
    }

    /// @dev The start token ID for the contract.
    function _startTokenId() internal pure returns (uint256) {
        return 1;
    }

    function startTokenId() public pure returns (uint256) {
        return _startTokenId();
    }

    /*///////////////////////////////////////////////////////////////
                            Migration logic
    //////////////////////////////////////////////////////////////*/

    function _mintMigratedTokens(address _to, uint256 _tokenId) internal virtual override {
        _safeMint(_to, _tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Collects and distributes the primary sale value of NFTs being claimed.
    function _collectPriceOnClaim(
        address _primarySaleRecipient,
        uint256 _quantityToClaim,
        address _currency,
        uint256 _pricePerToken
    ) internal override {
        if (_pricePerToken == 0) {
            if (msg.value != 0) {
                revert OpenEditionInvalidMsgValue(0, msg.value);
            }
            return;
        }

        uint256 totalPrice = _quantityToClaim * _pricePerToken;

        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            if (msg.value != totalPrice) {
                revert OpenEditionInvalidMsgValue(totalPrice, msg.value);
            }
        } else {
            if (msg.value != 0) {
                revert OpenEditionInvalidMsgValue(0, msg.value);
            }
        }

        address saleRecipient = _primarySaleRecipient == address(0) ? primarySaleRecipient() : _primarySaleRecipient;

        CurrencyTransferLib.transferCurrency(_currency, msg.sender, saleRecipient, totalPrice);
    }

    /// @dev Transfers the NFTs being claimed.
    function _transferTokensOnClaim(
        address _to,
        uint256 _quantityBeingClaimed
    ) internal override returns (uint256 tokenIdToClaim) {
        tokenIdToClaim = nextTokenIdToClaim;

        for (uint256 i = 0; i < _quantityBeingClaimed; i += 1) {
            _safeMint(_to, tokenIdToClaim);
            tokenIdToClaim += 1;
        }

        nextTokenIdToClaim = tokenIdToClaim;
    }

    /// @dev Checks whether primary sale recipient can be set in the given execution context.
    function _canSetPrimarySaleRecipient() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether owner can be set in the given execution context.
    function _canSetOwner() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether royalty info can be set in the given execution context.
    function _canSetRoyaltyInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetClaimConditions() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Returns whether the shared metadata of tokens can be set in the given execution context.
    function _canSetSharedMetadata() internal view virtual override returns (bool) {
        return hasRole(MINTER_ROLE, msg.sender);
    }

    /// @notice Returns whether merkle root can be set in the given execution context.
    function _canSetMerkleRoot() internal virtual override returns (bool) {
        return hasRole(MIGRATION_ROLE, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /**
     * Returns the total amount of tokens minted in the contract.
     */
    function totalMinted() external view returns (uint256) {
        unchecked {
            return nextTokenIdToClaim - _startTokenId();
        }
    }

    /// @dev The tokenId of the next NFT that will be minted / lazy minted.
    function nextTokenIdToMint() external view returns (uint256) {
        return nextTokenIdToClaim;
    }

    /// @dev Burns `tokenId`. See {ERC721-_burn}.
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert OpenEditionNotApprovedOrOwner(msg.sender, tokenId);
        }

        _burn(tokenId);
    }

    /**
     *  @notice          View royalty info for a given token.
     *  @dev             Returns royalty recipient and bps for `_tokenId`.
     *  @param _tokenId  The tokenID of the NFT for which to query royalty info.
     */
    function getRoyaltyInfoForToken(uint256 _tokenId) public view override returns (address, uint16) {
        RoyaltyInfo memory royaltyForToken = royaltyInfoForToken[_tokenId];

        // if it's a migrated token and royalty has not been overriden yet
        if (_tokenId < migratedNextTokenId && royaltyForToken.recipient == address(0) && royaltyForToken.bps == 0) {
            return IRoyalty(_originalContract).getRoyaltyInfoForToken(_tokenId);
        }

        return
            royaltyForToken.recipient == address(0)
                ? (royaltyRecipient, uint16(royaltyBps))
                : (royaltyForToken.recipient, uint16(royaltyForToken.bps));
    }

    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        // if transfer is restricted on the contract, we still want to allow burning and minting
        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            if (!hasRole(TRANSFER_ROLE, from) && !hasRole(TRANSFER_ROLE, to)) {
                revert OpenEditionTransferRestricted(from, to);
            }
        }
    }

    function _dropMsgSender() internal view virtual override returns (address) {
        return msg.sender;
    }
}

