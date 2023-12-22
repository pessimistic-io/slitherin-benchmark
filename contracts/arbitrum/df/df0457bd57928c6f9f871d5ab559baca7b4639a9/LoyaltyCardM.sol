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

// Interface
import "./ILoyaltyCard.sol";

// Base
import "./ERC721EnumerableUpgradeable.sol";

// Lib
import "./CurrencyTransferLib.sol";

// Extensions
import "./NFTMetadata.sol";
import "./SignatureMintERC721Upgradeable.sol";
import "./ContractMetadata.sol";
import "./Ownable.sol";
import "./RoyaltyMigration.sol";
import "./PrimarySale.sol";
import "./PlatformFee.sol";
import "./Multicall.sol";
import "./PermissionsEnumerable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./TokenMigrateERC721.sol";

/**
 *  @title LoyaltyCard
 *
 *  @custom:description This contract is a loyalty card NFT collection. Each NFT represents a loyalty card, and the NFT's metadata
 *                      contains the loyalty card's information. A loyalty card's metadata can be updated by an admin of the contract.
 *                      A loyalty card can be cancelled (i.e. 'burned') by its owner or an approved operator. A loyalty card can be revoked
 *                      (i.e. 'burned') without its owner's approval, by an admin of the contract.
 */
contract LoyaltyCardM is
    ILoyaltyCard,
    ContractMetadata,
    Ownable,
    RoyaltyMigration,
    PrimarySale,
    PlatformFee,
    Multicall,
    PermissionsEnumerable,
    ReentrancyGuardUpgradeable,
    NFTMetadata,
    SignatureMintERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    TokenMigrateERC721
{
    /// @dev Unable to transfer the token due to missing role
    error LoyaltyTransferRestricted(address from, address to);

    /// @dev Invalid msg.value
    error LoyaltyInvalidMsgValue(uint256 expected, uint256 actual);

    /// @dev Invalid mint quantity
    error LoyaltyInvalidQuantity(uint256 expected, uint256 actual);

    /// @dev Invalid fee
    error LoyaltyInvalidFeeExceedTotalPrice(uint256 totalPrice, uint256 fee);

    /// @dev Non-existent token id
    error LoyaltyInvalidTokenId();

    /// @dev token owner or approved
    error LoyaltyNotApprovedOrOwner(address sender, uint256 tokenId);

    /*///////////////////////////////////////////////////////////////
                                State variables
    //////////////////////////////////////////////////////////////*/

    /// @dev Only TRANSFER_ROLE holders can have tokens transferred from or to them, during restricted transfers.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can sign off on `MintRequest`s.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Only METADATA_ROLE holders can update NFT metadata.
    bytes32 private constant METADATA_ROLE = keccak256("METADATA_ROLE");
    /// @dev Only REVOKE_ROLE holders can revoke a loyalty card.
    bytes32 private constant REVOKE_ROLE = keccak256("REVOKE_ROLE");
    /// @dev Only MIGRATION holders can set merkle root for migration
    bytes32 private constant MIGRATION_ROLE = keccak256("MIGRATION_ROLE");

    /// @dev Max bps in the thirdweb system.
    uint256 private constant MAX_BPS = 10_000;

    /// @dev Next tokenId to be minted.
    uint256 public nextTokenIdToMint;

    /// @dev Next tokenId that was to be claimed on original contract.
    uint256 private migratedNextTokenId;

    /*///////////////////////////////////////////////////////////////
                        Constructor + initializer
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
        __ERC721_init(LoyaltyCardM(__originalContract).name(), LoyaltyCardM(__originalContract).symbol());
        __SignatureMintERC721_init();
        __ReentrancyGuard_init();

        {
            _setupOriginalContract(__originalContract);
            _setupMerkleRoot(_ownershipMerkleRoot);

            uint256 _nextIdToMint = LoyaltyCardM(__originalContract).nextTokenIdToMint();
            nextTokenIdToMint = _nextIdToMint;
            migratedNextTokenId = _nextIdToMint;

            (address royaltyRecipient, uint16 royaltyBps) = LoyaltyCardM(__originalContract).getDefaultRoyaltyInfo();
            (address platformFeeRecipient, uint256 platformFeeBps) = LoyaltyCardM(__originalContract)
                .getPlatformFeeInfo();

            address primarySaleRecipient = LoyaltyCardM(__originalContract).primarySaleRecipient();

            if (platformFeeRecipient != address(0)) {
                _setupPlatformFeeInfo(platformFeeRecipient, platformFeeBps);
            }

            if (royaltyRecipient != address(0)) {
                _setupDefaultRoyaltyInfo(royaltyRecipient, royaltyBps);
            }

            if (primarySaleRecipient != address(0)) {
                _setupPrimarySaleRecipient(primarySaleRecipient);
            }

            try LoyaltyCardM(__originalContract).getPlatformFeeType() returns (PlatformFeeType _feeType) {
                (address flatFeeRecipient, uint256 flatFee) = LoyaltyCardM(__originalContract).getFlatPlatformFeeInfo();

                _setupFlatPlatformFeeInfo(flatFeeRecipient, flatFee);
                _setupPlatformFeeType(_feeType);
            } catch {}
        }

        _setupContractURI(_contractURI);
        _setupOwner(_defaultAdmin);

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);

        _setupRole(TRANSFER_ROLE, _defaultAdmin);

        _setupRole(METADATA_ROLE, _defaultAdmin);
        _setRoleAdmin(METADATA_ROLE, METADATA_ROLE);

        _setupRole(REVOKE_ROLE, _defaultAdmin);
        _setRoleAdmin(REVOKE_ROLE, REVOKE_ROLE);

        _setupRole(MIGRATION_ROLE, _defaultAdmin);
        _setRoleAdmin(MIGRATION_ROLE, REVOKE_ROLE);
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        if (_tokenId < migratedNextTokenId && bytes(_tokenURI[_tokenId]).length == 0) {
            return LoyaltyCardM(_originalContract).tokenURI(_tokenId);
        }
        return _getTokenURI(_tokenId);
    }

    /// @dev See ERC 165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721EnumerableUpgradeable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || type(IERC2981).interfaceId == interfaceId;
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Mints an NFT according to the provided mint request. Always mints 1 NFT.
    function mintWithSignature(
        MintRequest calldata _req,
        bytes calldata _signature
    ) external payable nonReentrant returns (address signer) {
        if (_req.quantity != 1) {
            revert LoyaltyInvalidQuantity(1, _req.quantity);
        }

        signer = _processRequest(_req, _signature);
        address receiver = _req.to;
        uint256 tokenIdMinted = _mintTo(receiver, _req.uri);

        // Set royalties, if applicable.
        if (_req.royaltyRecipient != address(0) && _req.royaltyBps != 0) {
            _setupRoyaltyInfoForToken(tokenIdMinted, _req.royaltyRecipient, _req.royaltyBps);
        }

        _collectPrice(_req.primarySaleRecipient, _req.quantity, _req.currency, _req.pricePerToken);

        emit TokensMintedWithSignature(signer, receiver, tokenIdMinted, _req);
    }

    /// @dev Lets an account with MINTER_ROLE mint an NFT. Always mints 1 NFT.
    function mintTo(address _to, string calldata _uri) external onlyRole(MINTER_ROLE) returns (uint256 tokenIdMinted) {
        tokenIdMinted = _mintTo(_to, _uri);
        emit TokensMinted(_to, tokenIdMinted, _uri);
    }

    /// @dev Burns `tokenId`. See {ERC721-_burn}.
    function cancel(uint256 tokenId) external virtual override {
        //solhint-disable-next-line max-line-length
        if (!_isApprovedOrOwner(msg.sender, tokenId)) {
            revert LoyaltyNotApprovedOrOwner(msg.sender, tokenId);
        }

        _burn(tokenId);
    }

    /// @dev Burns `tokenId`. See {ERC721-_burn}.
    function revoke(uint256 tokenId) external virtual override onlyRole(REVOKE_ROLE) {
        _burn(tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                            Migration logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Mints migrated tokens to recipient.
    function _mintMigratedTokens(address _to, uint256 _tokenId) internal override {
        // Note: LoyaltyCard.tokenURI does not revert even if token is non-existent (i.e. burned)
        _setTokenURI(_tokenId, LoyaltyCardM(_originalContract).tokenURI(_tokenId));
        _safeMint(_to, _tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the total amount of tokens minted in the contract.
     */
    function totalMinted() external view returns (uint256) {
        return nextTokenIdToMint;
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

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Collects and distributes the primary sale value of NFTs being claimed.
    function _collectPrice(
        address _primarySaleRecipient,
        uint256 _quantityToClaim,
        address _currency,
        uint256 _pricePerToken
    ) internal {
        if (_pricePerToken == 0) {
            if (msg.value != 0) {
                revert LoyaltyInvalidMsgValue(0, msg.value);
            }
            return;
        }

        uint256 totalPrice = _quantityToClaim * _pricePerToken;
        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            if (msg.value != totalPrice) {
                revert LoyaltyInvalidMsgValue(totalPrice, msg.value);
            }
        } else {
            if (msg.value != 0) {
                revert LoyaltyInvalidMsgValue(0, msg.value);
            }
        }

        address saleRecipient = _primarySaleRecipient == address(0) ? primarySaleRecipient() : _primarySaleRecipient;

        uint256 fees;
        address feeRecipient;

        PlatformFeeType feeType = getPlatformFeeType();
        if (feeType == PlatformFeeType.Flat) {
            (feeRecipient, fees) = getFlatPlatformFeeInfo();
        } else {
            uint16 platformFeeBps;
            (feeRecipient, platformFeeBps) = getPlatformFeeInfo();
            fees = (totalPrice * platformFeeBps) / MAX_BPS;
        }

        if (fees > totalPrice) {
            revert LoyaltyInvalidFeeExceedTotalPrice(totalPrice, fees);
        }

        CurrencyTransferLib.transferCurrency(_currency, msg.sender, feeRecipient, fees);
        CurrencyTransferLib.transferCurrency(_currency, msg.sender, saleRecipient, totalPrice - fees);
    }

    /// @dev Mints an NFT to `to`
    function _mintTo(address _to, string calldata _uri) internal returns (uint256 tokenIdToMint) {
        tokenIdToMint = nextTokenIdToMint;
        nextTokenIdToMint += 1;

        _setTokenURI(tokenIdToMint, _uri);
        _safeMint(_to, tokenIdToMint);
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
                revert LoyaltyTransferRestricted(from, to);
            }
        }
    }

    /// @dev Checks whether platform fee info can be set in the given execution context.
    function _canSetPlatformFeeInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

    /// @dev Returns whether a given address is authorized to sign mint requests.
    function _isAuthorizedSigner(address _signer) internal view override returns (bool) {
        return hasRole(MINTER_ROLE, _signer);
    }

    /// @dev Returns whether metadata can be set in the given execution context.
    function _canSetMetadata() internal view virtual override returns (bool) {
        return hasRole(METADATA_ROLE, msg.sender);
    }

    /// @dev Returns whether metadata can be frozen in the given execution context.
    function _canFreezeMetadata() internal view virtual override returns (bool) {
        return hasRole(METADATA_ROLE, msg.sender);
    }

    /// @notice Returns whether merkle root can be set in the given execution context.
    function _canSetMerkleRoot() internal virtual override returns (bool) {
        return hasRole(MIGRATION_ROLE, msg.sender);
    }
}

