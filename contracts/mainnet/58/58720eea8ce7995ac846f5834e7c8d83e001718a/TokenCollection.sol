// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./SafeMathUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./ERC721BurnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./BaseCollection.sol";
import "./Redeemables.sol";

contract TokenCollection is
    Redeemables,
    BaseCollection,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable
{
    using SafeMathUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        string memory name_,
        string memory symbol_,
        address treasury_,
        address royalty_,
        uint96 royaltyFee_
    ) public override initializer {
        __ERC721_init(name_, symbol_);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Burnable_init();

        __BaseCollection_init(owner_, treasury_, royalty_, royaltyFee_);
        _tokenIdCounter.increment();
    }

    function mint(
        address to,
        uint256 quantity,
        string memory uri
    ) external onlyRolesOrOwner(MANAGER_ROLE) {
        _mint(to, quantity, uri);
    }

    function createRedeemable(
        string memory uri,
        uint256 price,
        uint256 maxQuantity,
        uint256 maxPerWallet,
        uint256 maxPerMint
    ) external onlyRolesOrOwner(MANAGER_ROLE) {
        _createRedeemable(uri, price, maxQuantity, maxPerWallet, maxPerMint);
    }

    function setMerkleRoot(uint256 redeemableId, bytes32 newRoot)
        external
        onlyRolesOrOwner(MANAGER_ROLE)
    {
        _setMerkleRoot(redeemableId, newRoot);
    }

    function setTokenURI(uint256 tokenId, string memory newUri)
        external
        onlyRolesOrOwner(MANAGER_ROLE)
    {
        _setTokenURI(tokenId, newUri);
    }

    function invalidate(uint256 redeemableId)
        external
        onlyRolesOrOwner(MANAGER_ROLE)
    {
        _invalidate(redeemableId);
    }

    function revoke(uint256 redeemableId)
        external
        onlyRolesOrOwner(MANAGER_ROLE)
    {
        _revoke(redeemableId);
    }

    function redeem(
        uint256 redeemableId,
        uint256 quantity,
        bytes calldata signature,
        bytes32[] calldata proof
    ) external payable {
        Redeemable memory redeemable = redeemableAt(redeemableId);

        unchecked {
            _totalRevenue = _totalRevenue.add(msg.value);
        }
        _niftyKit.addFees(msg.value);
        _mint(_msgSender(), quantity, redeemable.tokenURI);
        _redeem(redeemableId, quantity, signature, owner(), proof);
    }

    function _mint(
        address to,
        uint256 quantity,
        string memory uri
    ) internal {
        for (uint256 i = 0; i < quantity; ) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uri);
            unchecked {
                i++;
            }
        }
    }

    function isApprovedForAll(address owner, address operator)
        public
        view
        override(ERC721Upgradeable, IERC721Upgradeable)
        returns (bool isOperator)
    {
        if (_operatorRegistry != address(0)) {
            bytes32 identifier = IOperatorRegistry(_operatorRegistry)
                .getIdentifier(operator);

            if (_allowedOperators[identifier]) return true;
            if (_blockedOperators[identifier]) return false;
        }

        return ERC721Upgradeable.isApprovedForAll(owner, operator);
    }

    function approve(address to, uint256 tokenId)
        public
        virtual
        override(ERC721Upgradeable, IERC721Upgradeable)
        preventBlockedOperator(to)
    {
        ERC721Upgradeable.approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override(ERC721Upgradeable, IERC721Upgradeable)
        preventBlockedOperator(operator)
    {
        ERC721Upgradeable.setApprovalForAll(operator, approved);
    }

    // The following functions are overrides required by Solidity.
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return ERC721URIStorageUpgradeable.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
    {
        ERC721URIStorageUpgradeable._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, BaseCollection)
        returns (bool)
    {
        return
            ERC721Upgradeable.supportsInterface(interfaceId) ||
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            BaseCollection.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }
}

