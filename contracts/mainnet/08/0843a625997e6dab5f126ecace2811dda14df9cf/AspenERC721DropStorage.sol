// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8;

/// ========== External imports ==========
import "./ERC721EnumerableUpgradeable.sol";
import "./IERC2981Upgradeable.sol";
import "./StringsUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./draft-EIP712Upgradeable.sol";
import "./DefaultOperatorFiltererUpgradeable.sol";

/// ========== Features ==========
import "./ERC2771ContextUpgradeable.sol";

import "./DropERC721DataTypes.sol";
import "./TermsDataTypes.sol";

import "./errors_IErrors.sol";

import "./AspenERC721DropLogic.sol";
import "./TermsLogic.sol";

import "./IDropClaimCondition.sol";
import "./IContractMetadata.sol";
import "./IRoyalty.sol";
import "./IOwnable.sol";

abstract contract AspenERC721DropStorage is
    Initializable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC721EnumerableUpgradeable,
    EIP712Upgradeable,
    DefaultOperatorFiltererUpgradeable
{
    /// ================================
    /// =========== Libraries ==========
    /// ================================
    using StringsUpgradeable for uint256;
    using AspenERC721DropLogic for DropERC721DataTypes.ClaimData;
    using TermsLogic for TermsDataTypes.Terms;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    /// =============================
    /// =========== Events ==========
    /// =============================
    /// @dev Emitted when the wallet claim count for an address is updated.
    event WalletClaimCountUpdated(address indexed wallet, uint256 count);
    /// @dev Emitted when the global max wallet claim count is updated.
    event MaxWalletClaimCountUpdated(uint256 count);

    /// ===============================================
    /// =========== State variables - public ==========
    /// ===============================================
    /// @dev Contract level metadata.
    string public _contractUri;
    /// @dev Token name
    string public __name;
    /// @dev Token symbol
    string public __symbol;
    /// @dev Only transfers to or from TRANSFER_ROLE holders are valid, when transfers are restricted.
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can lazy mint NFTs.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Only ISSUER_ROLE holders can issue NFTs.
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    /// @dev Offset for token IDs.
    uint8 public constant TOKEN_INDEX_OFFSET = 1;
    /// @dev If true, users cannot claim.
    bool public claimIsPaused = false;
    /// ================================================
    /// =========== State variables - private ==========
    /// ================================================
    /// @dev Owner of the contract (purpose: OpenSea compatibility)
    address public _owner;
    /// @dev The (default) address that receives all royalty value.
    address public royaltyRecipient;
    /// @dev Token ID => royalty recipient and bps for token
    mapping(uint256 => IRoyaltyV0.RoyaltyInfo) public royaltyInfoForToken;
    /// @dev address of delegate logic contract
    address public delegateLogicContract;
    /// @dev enable/disable operator filterer.
    bool public operatorFiltererEnabled;

    bytes32 public constant MESSAGE_HASH =
        keccak256("AcceptTerms(address acceptor,string termsURI,uint8 termsVersion)");

    struct AcceptTerms {
        address acceptor;
        string termsURI;
        uint8 termsVersion;
    }

    DropERC721DataTypes.ClaimData claimData;
    TermsDataTypes.Terms termsData;

    modifier isValidTokenId(uint256 _tokenId) {
        if (_tokenId <= 0) revert InvalidTokenId(_tokenId);
        _;
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721EnumerableUpgradeable, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            AccessControlEnumerableUpgradeable.supportsInterface(interfaceId);
    }

    /// @dev See {ERC721-_beforeTokenTransfer}.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId);

        // if transfer is restricted on the contract, we still want to allow burning and minting
        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            if (!(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to))) revert InvalidPermission();
        }

        if (to != address(this)) {
            if (termsData.termsActivated) {
                if (!termsData.termsAccepted[to] || termsData.termsVersion != termsData.acceptedVersion[to])
                    revert TermsNotAccepted(to, termsData.termsURI, termsData.termsVersion);
            }
        }
    }

    /// ======================================
    /// =========== Miscellaneous ============
    /// ======================================
    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }
}

