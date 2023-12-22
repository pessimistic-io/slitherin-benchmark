// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./NftMarket.sol";

import "./ERC721Upgradeable.sol";
import "./IERC721Upgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";

contract GNft is NftMarket, ERC721Upgradeable, IERC721ReceiverUpgradeable {
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    address public lendPoolLoan;
    mapping(uint256 => address) private _minters;

    /* ========== MODIFIERS ========== */

    modifier onlyLendPoolLoan() {
        require(msg.sender == lendPoolLoan, "GNft: only lendPoolLoan contract");
        _;
    }

    /* ========== INITIALIZER ========== */

    function initialize(string calldata gNftName, string calldata gNftSymbol, address _lendPoolLoan) external initializer {
        __ERC721_init(gNftName, gNftSymbol);
        __GMarket_init();
        lendPoolLoan = _lendPoolLoan;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function mint(address to, uint256 tokenId) external override onlyLendPoolLoan nonReentrant {
        require(IERC721Upgradeable(underlying).ownerOf(tokenId) == msg.sender, "GNft: caller is not owner");

        _mint(to, tokenId);

        _minters[tokenId] = msg.sender;

        IERC721Upgradeable(underlying).safeTransferFrom(msg.sender, address(this), tokenId);

        emit Mint(msg.sender, underlying, tokenId, to);
    }

    function burn(uint256 tokenId) external override nonReentrant {
        require(_exists(tokenId), "GNft: nonexist token");
        require(_minters[tokenId] == msg.sender, "GNft: caller is not minter");

        address tokenOwner = IERC721Upgradeable(underlying).ownerOf(tokenId);

        _burn(tokenId);

        delete _minters[tokenId];

        IERC721Upgradeable(underlying).safeTransferFrom(address(this), msg.sender, tokenId);

        emit Burn(msg.sender, underlying, tokenId, tokenOwner);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        to;
        tokenId;
        revert("APPROVAL_NOT_SUPPORTED");
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        operator;
        approved;
        revert("APPROVAL_NOT_SUPPORTED");
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        from;
        to;
        tokenId;
        _data;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Upgradeable) {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    /* ========== VIEWS ========== */

    function minterOf(uint256 tokenId) public view override returns (address) {
        address _minter = _minters[tokenId];
        require(_minter != address(0), "GNft: minter query for nonexistent token");
        return _minter;
    }

    /* ========== RECEIVER FUNCTIONS ========== */

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}

