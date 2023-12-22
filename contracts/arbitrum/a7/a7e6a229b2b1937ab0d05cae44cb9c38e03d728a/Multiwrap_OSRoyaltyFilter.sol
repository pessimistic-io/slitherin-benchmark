// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

//  ==========  External imports    ==========
import "./ERC721EnumerableUpgradeable.sol";

import "./MulticallUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC2981Upgradeable.sol";

//  ==========  Internal imports    ==========

import "./IMultiwrap.sol";
import "./ERC2771ContextUpgradeable.sol";

//  ==========  Features    ==========

import "./ContractMetadata.sol";
import "./Royalty.sol";
import "./Ownable.sol";
import "./PermissionsEnumerable.sol";
import { TokenStore, ERC1155Receiver, IERC1155Receiver } from "./TokenStore.sol";

// OpenSea operator filter
import "./DefaultOperatorFiltererUpgradeable.sol";

contract Multiwrap_OSRoyaltyFilter is
    Initializable,
    ContractMetadata,
    Royalty,
    Ownable,
    PermissionsEnumerable,
    TokenStore,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    MulticallUpgradeable,
    DefaultOperatorFiltererUpgradeable,
    ERC721EnumerableUpgradeable,
    IMultiwrap
{
    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant MODULE_TYPE = bytes32("Multiwrap");
    uint256 private constant VERSION = 1;

    /// @dev Only transfers to or from TRANSFER_ROLE holders are valid, when transfers are restricted.
    bytes32 private constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    /// @dev Only MINTER_ROLE holders can wrap tokens, when wrapping is restricted.
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @dev Only UNWRAP_ROLE holders can unwrap tokens, when unwrapping is restricted.
    bytes32 private constant UNWRAP_ROLE = keccak256("UNWRAP_ROLE");
    /// @dev Only assets with ASSET_ROLE can be wrapped, when wrapping is restricted to particular assets.
    bytes32 private constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /// @dev The next token ID of the NFT to mint.
    uint256 public nextTokenIdToMint;

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

    constructor(address _nativeTokenWrapper) TokenStore(_nativeTokenWrapper) initializer {}

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _royaltyRecipient,
        uint256 _royaltyBps
    ) external initializer {
        // Initialize inherited contracts, most base-like -> most derived.
        __ReentrancyGuard_init();
        __ERC2771Context_init(_trustedForwarders);
        __ERC721_init(_name, _symbol);
        __DefaultOperatorFilterer_init();

        // Initialize this contract's state.
        _setupDefaultRoyaltyInfo(_royaltyRecipient, _royaltyBps);
        _setupOwner(_defaultAdmin);
        _setupContractURI(_contractURI);

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(MINTER_ROLE, _defaultAdmin);
        _setupRole(TRANSFER_ROLE, _defaultAdmin);

        // note: see `_beforeTokenTransfer` for TRANSFER_ROLE behaviour.
        _setupRole(TRANSFER_ROLE, address(0));

        // note: see `onlyRoleWithSwitch` for UNWRAP_ROLE behaviour.
        _setupRole(UNWRAP_ROLE, address(0));

        // note: see `onlyRoleWithSwitch` for UNWRAP_ROLE behaviour.
        _setupRole(ASSET_ROLE, address(0));
    }

    /*///////////////////////////////////////////////////////////////
                            Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyRoleWithSwitch(bytes32 role) {
        _checkRoleWithSwitch(role, _msgSender());
        _;
    }

    /*///////////////////////////////////////////////////////////////
                        Generic contract logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the type of the contract.
    function contractType() external pure returns (bytes32) {
        return MODULE_TYPE;
    }

    /// @dev Returns the version of the contract.
    function contractVersion() external pure returns (uint8) {
        return uint8(VERSION);
    }

    /// @dev Lets the contract receive ether to unwrap native tokens.
    receive() external payable {
        require(msg.sender == nativeTokenWrapper, "caller not native token wrapper.");
    }

    /*///////////////////////////////////////////////////////////////
                        ERC 165 / 721 / 2981 logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the URI for a given tokenId.
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return getUriOfBundle(_tokenId);
    }

    /// @dev See ERC 165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Receiver, ERC721EnumerableUpgradeable, IERC165) returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC721Upgradeable).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC2981Upgradeable).interfaceId;
    }

    /*///////////////////////////////////////////////////////////////
                    Wrapping / Unwrapping logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Wrap multiple ERC1155, ERC721, ERC20 tokens into a single wrapped NFT.
    function wrap(
        Token[] calldata _tokensToWrap,
        string calldata _uriForWrappedToken,
        address _recipient
    ) external payable nonReentrant onlyRoleWithSwitch(MINTER_ROLE) returns (uint256 tokenId) {
        if (!hasRole(ASSET_ROLE, address(0))) {
            for (uint256 i = 0; i < _tokensToWrap.length; i += 1) {
                _checkRole(ASSET_ROLE, _tokensToWrap[i].assetContract);
            }
        }

        tokenId = nextTokenIdToMint;
        nextTokenIdToMint += 1;

        _storeTokens(_msgSender(), _tokensToWrap, _uriForWrappedToken, tokenId);

        _safeMint(_recipient, tokenId);

        emit TokensWrapped(_msgSender(), _recipient, tokenId, _tokensToWrap);
    }

    /// @dev Unwrap a wrapped NFT to retrieve underlying ERC1155, ERC721, ERC20 tokens.
    function unwrap(uint256 _tokenId, address _recipient) external nonReentrant onlyRoleWithSwitch(UNWRAP_ROLE) {
        require(_tokenId < nextTokenIdToMint, "wrapped NFT DNE.");
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "caller not approved for unwrapping.");

        _burn(_tokenId);
        _releaseTokens(_recipient, _tokenId);

        emit TokensUnwrapped(_msgSender(), _recipient, _tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                        Getter functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the underlying contents of a wrapped NFT.
    function getWrappedContents(uint256 _tokenId) external view returns (Token[] memory contents) {
        uint256 total = getTokenCountOfBundle(_tokenId);
        contents = new Token[](total);

        for (uint256 i = 0; i < total; i += 1) {
            contents[i] = getTokenOfBundle(_tokenId, i);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        Internal functions
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns whether owner can be set in the given execution context.
    function _canSetOwner() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev Returns whether royalty info can be set in the given execution context.
    function _canSetRoyaltyInfo() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev Returns whether contract metadata can be set in the given execution context.
    function _canSetContractURI() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {ERC721-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        // if transfer is restricted on the contract, we still want to allow burning and minting
        if (!hasRole(TRANSFER_ROLE, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(TRANSFER_ROLE, from) || hasRole(TRANSFER_ROLE, to), "!TRANSFER_ROLE");
        }
    }

    /// @dev See {ERC721-setApprovalForAll}.
    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    /// @dev See {ERC721-approve}.
    function approve(
        address operator,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    /// @dev See {ERC721-_transferFrom}.
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /// @dev See {ERC721-_safeTransferFrom}.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /// @dev See {ERC721-_safeTransferFrom}.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721Upgradeable, IERC721Upgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

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

