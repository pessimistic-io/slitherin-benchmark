// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import {Reentrancy} from "./Reentrancy.sol";
import {ERC721, IERC721, IERC165} from "./ERC721.sol";
import {IERC721Metadata} from "./IERC721.sol";
import {IERC2309} from "./IERC2309.sol";
import {IERC2981} from "./IERC2981.sol";
import {IEditions, IEditionsEvents} from "./IEditions.sol";

import {IRenderer} from "./IRenderer.sol";

import {ITreasuryConfig} from "./ITreasuryConfig.sol";
import {IMirrorTreasury} from "./IMirrorTreasury.sol";
import {IMirrorFeeConfig} from "./MirrorFeeConfig.sol";

/**
 * @title Editions
 * @author MirrorXYZ
 */
contract Editions is
    Ownable,
    Pausable,
    Reentrancy,
    ERC721,
    IERC721Metadata,
    IERC2309,
    IERC2981,
    IEditions,
    IEditionsEvents
{
    // ============ Deployment ============

    /// @notice Address that deploys and initializes clones
    address public immutable override factory;

    // ============ Fee Configuration ============

    /// @notice Address for Mirror fee configuration.
    address public immutable override feeConfig;

    /// @notice Address for Mirror treasury configuration.
    address public immutable override treasuryConfig;

    // ============ ERC721 Metadata ============

    /// @notice Edition name
    string public override name;

    /// @notice Ediiton symbol
    string public override symbol;

    /// @notice Edition baseURI
    string public override baseURI;

    // ============ Edition Data ============

    /// @notice Next tokenId to mint
    uint256 internal currentTokenId;

    /// @notice Edition price
    uint256 public override price;

    /// @notice Edition limit
    uint256 public override limit;

    /// @notice Edition contentHash
    bytes32 public override contentHash;

    // ============ Royalty Info (ERC2981) ============

    /// @notice Account that will receive royalties
    /// @dev set address(0) to avoid royalties
    address public override royaltyRecipient;

    /// @notice Royalty Basis Points
    uint256 public override royaltyBPS;

    // ============ Rendering ============

    /// @notice Rendering contract
    address public override renderer;

    // ============ Pre allocation ============

    /// @notice Allocation recipient (consecutive transfer)
    address internal allocationRecipient;

    /// @notice Allocation count (consecutive transfer)
    uint256 internal allocationCount;

    // ============ Constructor ============
    constructor(
        address factory_,
        address feeConfig_,
        address treasuryConfig_
    ) Ownable(address(0)) Pausable(false) {
        factory = factory_;
        feeConfig = feeConfig_;
        treasuryConfig = treasuryConfig_;
    }

    // ============ Initializing ============

    /// @notice Initialize metadata
    /// @param owner_ the clone owner
    /// @param name_ the name for the edition clone
    /// @param symbol_ the symbol for the edition clone
    /// @param baseURI_ the baseURI for the edition clone
    /// @param edition_ the parameters for the edition sale
    /// @param paused_ the pause state for the edition sale
    function initialize(
        address owner_,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        Edition memory edition_,
        bool paused_
    ) external override {
        require(msg.sender == factory, "unauthorized caller");

        // store erc721 metadata
        name = name_;
        symbol = symbol_;
        baseURI = baseURI_;

        // store edition data
        price = edition_.price;
        limit = edition_.limit;
        contentHash = edition_.contentHash;

        // set pause status
        if (paused_) {
            _pause();
        }

        // store owner
        _setOwner(address(0), owner_);
    }

    // ============ Pause Methods ============

    /// @notice Unpause edition sale
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @notice Pause edition sale
    function pause() external override onlyOwner {
        _pause();
    }

    // ============ Allocation ============

    /// @notice Allocates `count` editions to `recipient`
    /// @dev Throws if an edition has been purchased already or `count` exceeds limit
    /// @param recipient the account to receive tokens
    /// @param count the number of tokens to mint to `recipient`
    function allocate(address recipient, uint256 count)
        external
        override
        onlyOwner
    {
        // check that no purchases have happened and count does not exceed limit
        require(
            currentTokenId == 0 && (limit == 0 || count <= limit),
            "cannot allocate"
        );

        // set allocation recipient
        allocationRecipient = recipient;
        allocationCount = count;

        // update tokenId
        currentTokenId = count;

        // update balance
        _balances[recipient] = count;

        // emit transfer
        emit ConsecutiveTransfer(
            // fromTokenId
            0,
            // toTokenId
            count - 1,
            // fromAddress
            address(0),
            // toAddress
            recipient
        );
    }

    /// @notice Finds the owner of a token
    /// @dev this method takes into account allocation
    function ownerOf(uint256 tokenId) public view override returns (address) {
        address _owner = _owners[tokenId];

        // if there is not owner set,
        // and the tokenId is within the allocation count
        // the allocationRecipient owns it
        if (_owner == address(0) && tokenId < allocationCount) {
            return allocationRecipient;
        }

        require(_owner != address(0), "ERC721: query for nonexistent token");

        return _owner;
    }

    // ============ Purchase ============

    /// @notice Purchase an edition
    /// @dev throws if sale is paused or incorrect value is sent
    /// @param recipient the account to receive the edition
    function purchase(address recipient)
        external
        payable
        override
        whenNotPaused
        returns (uint256 tokenId)
    {
        require(msg.value == price, "incorrect value");

        return _purchase(recipient);
    }

    // ============ Minting ============

    /// @notice Mint an edition
    /// @dev throws if called by a non-owner
    /// @param recipient the account to receive the edition
    function mint(address recipient)
        external
        override
        onlyOwner
        returns (uint256 tokenId)
    {
        tokenId = _getTokenIdAndMint(recipient);
    }

    /// @notice Allows the owner to set a global limit on the total supply
    /// @dev throws if attempting to increase the limit
    function setLimit(uint256 limit_) external override onlyOwner {
        // enforce that the limit should only ever decrease once set
        require(
            limit == 0 || limit_ < limit,
            "limit must be < than current limit"
        );

        // announce the change in limit
        emit EditionLimitSet(
            // oldLimit
            limit,
            // newLimit
            limit_
        );

        // update the limit.
        limit = limit_;
    }

    // ============ ERC2981 Methods ============

    /// @notice Called with the sale price to determine how much royalty
    //  is owed and to whom
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _salePrice - the sale price of the NFT asset specified by _tokenId
    /// @return receiver - address of who should be sent the royalty payment
    /// @return royaltyAmount - the royalty payment amount for _salePrice
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = royaltyRecipient;
        royaltyAmount = (_salePrice * royaltyBPS) / 10_000;
    }

    /// @param royaltyRecipient_ the address that will receive royalties
    /// @param royaltyBPS_ the royalty amount in basis points (bps)
    function setRoyaltyInfo(
        address payable royaltyRecipient_,
        uint256 royaltyBPS_
    ) external override onlyOwner {
        require(
            royaltyBPS_ <= 10_000,
            "bps must be less than or equal to 10,000"
        );

        emit RoyaltyChange(
            // oldRoyaltyRecipient
            royaltyRecipient,
            // oldRoyaltyBPS
            royaltyBPS,
            // newRoyaltyRecipient
            royaltyRecipient_,
            // newRoyaltyBPS
            royaltyBPS_
        );

        royaltyRecipient = royaltyRecipient_;
        royaltyBPS = royaltyBPS_;
    }

    // ============ Rendering Methods ============

    /// @notice Set the renderer address
    /// @dev Throws if renderer is not the zero address
    function setRenderer(address renderer_) external override onlyOwner {
        require(renderer == address(0), "renderer already set");

        renderer = renderer_;

        emit RendererSet(
            // renderer
            renderer_
        );
    }

    /// @notice Allows the owner to set the baseURI
    function setBaseURI(string calldata baseURI_) external override onlyOwner {
        baseURI = baseURI_;
    }

    /// @notice Get contract metadata
    /// @dev If a renderer is set, return the renderer's metadata
    function contractURI() external view override returns (string memory) {
        if (renderer != address(0)) {
            return IRenderer(renderer).contractURI();
        }

        // Concatenate the components baseURI and metadata
        return string(abi.encodePacked(baseURI, "metadata"));
    }

    /// @notice Get `tokenId` URI or data
    /// @dev If a renderer is set, call renderer's tokenURI
    /// @param tokenId The tokenId used to request data
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "ERC721: query for nonexistent token");

        if (renderer != address(0)) {
            return IRenderer(renderer).tokenURI(tokenId);
        }

        return string(abi.encodePacked(baseURI, _toString(tokenId)));
    }

    // ============ Withdrawal ============

    /// @notice Set the price
    function setPrice(uint256 price_) external override onlyOwner {
        price = price_;

        emit PriceSet(
            // price
            price_
        );
    }

    function withdraw(uint16 feeBPS, address fundingRecipient)
        external
        onlyOwner
        nonReentrant
    {
        require(fundingRecipient != address(0), "must set fundingRecipient");

        _withdraw(feeBPS, fundingRecipient);
    }

    // ============ IERC165 Method ============

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC2981).interfaceId;
    }

    // ============ Internal Methods ============
    function _withdraw(uint16 feeBPS, address fundingRecipient) internal {
        // assert that the fee is valid
        require(IMirrorFeeConfig(feeConfig).isFeeValid(feeBPS), "invalid fee");

        // calculate the fee on the current balance, using the fee percentage
        uint256 fee = _feeAmount(address(this).balance, feeBPS);

        // if the fee is not zero, attempt to send it to the treasury
        if (fee != 0) {
            _sendEther(ITreasuryConfig(treasuryConfig).treasury(), fee);
        }

        // broadcast the withdrawal event – with balance and fee
        emit Withdrawal(
            // recipient
            fundingRecipient,
            // amount
            address(this).balance,
            // fee
            fee
        );

        // transfer the remaining balance to the fundingRecipient
        _sendEther(payable(fundingRecipient), address(this).balance);
    }

    function _sendEther(address payable recipient_, uint256 amount) internal {
        // ensure sufficient balance
        require(address(this).balance >= amount, "insufficient balance");
        // send the value
        (bool success, ) = recipient_.call{value: amount, gas: gasleft()}("");
        require(success, "recipient reverted");
    }

    function _feeAmount(uint256 amount, uint16 fee)
        internal
        pure
        returns (uint256)
    {
        return (amount * fee) / 10_000;
    }

    /// @dev ensure token has an owner, or token is within the allocation
    function _exists(uint256 tokenId) internal view override returns (bool) {
        return _owners[tokenId] != address(0) || tokenId < allocationCount;
    }

    /// @dev Mints token and emits purchase event
    function _purchase(address recipient) internal returns (uint256 tokenId) {
        // mint the token, get a tokenId
        tokenId = _getTokenIdAndMint(recipient);

        emit EditionPurchased(
            // tokenId
            tokenId,
            // recipient
            recipient
        );
    }

    /// @dev Mints and returns tokenId
    function _getTokenIdAndMint(address recipient)
        internal
        returns (uint256 tokenId)
    {
        // check that there are still tokens available to purchase
        require(limit == 0 || currentTokenId < limit, "sold out");

        // store tokenId to mint, and increment
        tokenId = currentTokenId++;

        // mint a new token for the recipient, using the `tokenId`.
        _mint(recipient, tokenId);
    }

    // From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Strings.sol
    function _toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

