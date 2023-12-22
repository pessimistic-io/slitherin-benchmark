// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";
import "./ECDSA.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./MerkleProof.sol";

import "./Context.sol";
import "./Strings.sol";
import "./ERC165.sol";
import "./draft-EIP712.sol";
import "./ERC721CreateX.sol";
import "./ERC2981PerTokenRoyalties.sol";
import "./ReentrancyGuard.sol";

contract CreateXSaleImpl is
    Ownable,
    ERC721CreateX,
    EIP712,
    ERC2981PerTokenRoyalties,
    ReentrancyGuard
{
    uint256 public CREATEX_MINT_FEE;
    uint256 public FREE_MINT_FEE_TIMESTAMP;

    function getCrateXMintFee() public view returns (uint256) {
        if (block.timestamp <= FREE_MINT_FEE_TIMESTAMP) {
            return 0;
        }
        return CREATEX_MINT_FEE;
    }

    //TODO: should be configabled
    address payable private immutable CreateX_MINT_FEE_RECIPIENT =
        payable(0x03f3609c47302aeb45b7208D8dc1042af75E723b);

    event Sale(
        address indexed to,
        uint256 indexed quantity,
        uint256 indexed pricePerToken,
        uint256 salePhase
    );

    error Purchase_TooManyForAddress();
    error Purchase_WrongPrice(uint256 correctPrice);
    error Presale_TooManyForAddress();
    error Presale_MerkleNotApproved();
    error Presale_Inactive();
    error Sale_Inactive();

    function _presaleActive() internal view returns (bool) {
        return
            salesConfig.presaleStart <= block.timestamp &&
            salesConfig.presaleEnd > block.timestamp;
    }

    function _publicSaleActive() internal view returns (bool) {
        return
            salesConfig.publicSaleStart <= block.timestamp &&
            salesConfig.publicSaleEnd > block.timestamp;
    }

    modifier onlyPresaleActive() {
        if (!_presaleActive()) {
            revert Presale_Inactive();
        }

        _;
    }

    /// @notice Public sale active
    modifier onlyPublicSaleActive() {
        if (!_publicSaleActive()) {
            revert Sale_Inactive();
        }
        _;
    }

    using Strings for uint256;
    struct SalesConfiguration {
        uint256 publicSalePrice;
        uint256 maxSalePurchasePerAddress;
        uint256 publicSaleStart;
        uint256 publicSaleEnd;
        uint256 presaleStart;
        uint256 preSalePrice;
        uint256 presaleMaxMintsPerAddress;
        uint256 presaleEnd;
        bytes32 presaleMerkleRoot;
        address fundsRecipient;
    }

    SalesConfiguration public salesConfig;

    mapping(address => uint256) public presaleMintsByAddress;
    mapping(address => uint256) public publicSaleMintsByAddress;

    bool internal isInited = false;

    string private constant version = "5";
    uint256 private _maxSupply;
    string private _baseUri;
    string private _collectionURI;

    /**
     * @dev if maxSupply==0; means unlimited
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseUri_,
        string memory collectionURI_
    ) ERC721CreateX(name_, symbol_) EIP712(name_, version) {
        _maxSupply = maxSupply_;
        _baseUri = baseUri_;
        _collectionURI = collectionURI_;
        isInited = true;
    }

    function initCreator(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseUri_,
        string calldata collectionURI_,
        address recipient,
        uint256 royaltyAmount,
        uint256 create_mint_fee,
        uint256 free_mint_fee_timestamp
    ) public {
        require(!isInited, "Can not reinited");
        isInited = true;

        _name = name_;
        _symbol = symbol_;
        _maxSupply = maxSupply_;
        _baseUri = baseUri_;
        _collectionURI = collectionURI_;

        RoyaltyInfo memory royaltyInfo_ = RoyaltyInfo(recipient, royaltyAmount);
        _setTokenRoyalty(royaltyInfo_);
        CREATEX_MINT_FEE = create_mint_fee;
        FREE_MINT_FEE_TIMESTAMP = free_mint_fee_timestamp;
    }

    function setSaleConfiguration(
        uint256 publicSalePrice,
        uint256 maxSalePurchasePerAddress,
        uint256 publicSaleStart,
        uint256 publicSaleEnd,
        uint256 presaleStart,
        uint256 presaleEnd,
        uint256 preSalePrice,
        uint256 presaleMaxMintsPerAddress,
        address fundsRecipient,
        bytes32 presaleMerkleRoot
    ) external onlyOwner {
        salesConfig.publicSalePrice = publicSalePrice;
        salesConfig.maxSalePurchasePerAddress = maxSalePurchasePerAddress;
        salesConfig.publicSaleStart = publicSaleStart;
        salesConfig.publicSaleEnd = publicSaleEnd;
        salesConfig.presaleStart = presaleStart;
        salesConfig.presaleEnd = presaleEnd;
        salesConfig.preSalePrice = preSalePrice;
        salesConfig.presaleMaxMintsPerAddress = presaleMaxMintsPerAddress;
        salesConfig.fundsRecipient = fundsRecipient;
        salesConfig.presaleMerkleRoot = presaleMerkleRoot;
    }

    function setTokenRoyalty(
        address recipient,
        uint256 royaltyAmount
    ) external onlyOwner {
        RoyaltyInfo memory royaltyInfo_ = RoyaltyInfo(recipient, royaltyAmount);
        _setTokenRoyalty(royaltyInfo_);
    }

    function saleDetails() external view returns (SalesConfiguration memory) {
        return salesConfig;
    }

    function purchase(
        address mintTo,
        uint256 quantity
    ) external payable onlyPublicSaleActive nonReentrant {
        return _handlePurchase(mintTo, quantity);
    }

    function _handlePurchase(address mintTo, uint256 quantity) internal {
        uint256 salePrice = salesConfig.publicSalePrice;

        uint256 CreateX_MINT_FEE = getCrateXMintFee();
        if (msg.value != (salePrice + CreateX_MINT_FEE) * quantity) {
            revert Purchase_WrongPrice(
                (salePrice + CreateX_MINT_FEE) * quantity
            );
        }

        // If max purchase per address == 0 there is no limit.
        // Any other number, the per address mint limit is that.
        if (
            salesConfig.maxSalePurchasePerAddress != 0 &&
            publicSaleMintsByAddress[mintTo] +
                quantity -
                presaleMintsByAddress[mintTo] >
            salesConfig.maxSalePurchasePerAddress
        ) {
            revert Purchase_TooManyForAddress();
        }

        __mintTo(mintTo, quantity);
        _payoutCreateXFee(quantity);
        _payoutPublicSale(quantity);

        publicSaleMintsByAddress[mintTo] += quantity;
        emit Sale({
            to: mintTo,
            quantity: quantity,
            pricePerToken: salesConfig.publicSalePrice,
            salePhase: 1
        });
    }

    function _payoutPublicSale(uint256 quantity) internal {
        uint256 fee = salesConfig.publicSalePrice * quantity;
        if (fee > 0) {
            (bool success, ) = salesConfig.fundsRecipient.call{
                value: fee,
                gas: 210_000
            }("");
            require(success, "_payoutPublicSale Transfer ETH failed");
        }
    }

    function purchasePresale(
        address mintTo,
        uint256 quantity,
        bytes32[] calldata merkleProof
    ) external payable nonReentrant onlyPresaleActive {
        _handlePurchasePresale(mintTo, quantity, merkleProof);
    }

    function _handlePurchasePresale(
        address mintTo,
        uint256 quantity,
        bytes32[] calldata merkleProof
    ) internal {
        if (
            !MerkleProof.verify(
                merkleProof,
                salesConfig.presaleMerkleRoot,
                keccak256(abi.encodePacked(mintTo))
            )
        ) {
            revert Presale_MerkleNotApproved();
        }

        uint256 CreateX_MINT_FEE = getCrateXMintFee();
        if (
            msg.value !=
            (salesConfig.preSalePrice + CreateX_MINT_FEE) * quantity
        ) {
            revert Purchase_WrongPrice(
                (salesConfig.preSalePrice + CreateX_MINT_FEE) * quantity
            );
        }

        presaleMintsByAddress[mintTo] += quantity;
        if (
            presaleMintsByAddress[mintTo] >
            salesConfig.presaleMaxMintsPerAddress
        ) {
            revert Presale_TooManyForAddress();
        }

        __mintTo(mintTo, quantity);
        _payoutPreSale(quantity);

        _payoutCreateXFee(quantity);

        emit Sale({
            to: mintTo,
            quantity: quantity,
            pricePerToken: salesConfig.preSalePrice,
            salePhase: 0
        });
    }

    function _payoutPreSale(uint256 quantity) internal {
        uint256 fee = salesConfig.preSalePrice * quantity;
        if (fee > 0) {
            (bool success, ) = salesConfig.fundsRecipient.call{
                value: fee,
                gas: 210_000
            }("");
            require(success, "_payoutPreSale Transfer ETH failed");
        }
    }

    function _payoutCreateXFee(uint256 quantity) internal {
        (, uint256 createXFee) = createXFeeForAmount(quantity);
        if (createXFee > 0) {
            (bool success, ) = CreateX_MINT_FEE_RECIPIENT.call{
                value: createXFee,
                gas: 210_000
            }("");
            require(success, "_payoutCreateXFee Transfer ETH failed");
        }
    }

    function createXFeeForAmount(
        uint256 quantity
    ) public view returns (address payable recipient, uint256 fee) {
        uint256 CreateX_MINT_FEE = getCrateXMintFee();

        recipient = CreateX_MINT_FEE_RECIPIENT;
        fee = CreateX_MINT_FEE * quantity;
    }

    function __mintTo(address to, uint256 quantity) internal {
        //totalSupply() tokenIndex starts from 0
        //if maxSupply==0; means unlimited
        require(
            _maxSupply == 0 || totalSupply() + quantity <= _maxSupply,
            "Mint count exceed MAX_SUPPLY!"
        );

        uint256 tokenId = totalSupply();
        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(to, tokenId + i);
        }
    }

    /**
     * @dev if maxSupply==0; means unlimited
     */
    function getMaxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    /**
     * @dev Override _collectionBaseURI, for collectionURI return collection Level URI
     */
    function _collectionBaseURI()
        internal
        view
        override
        returns (string memory)
    {
        return _collectionURI;
    }

    function setCollectionURI(
        string calldata newCollectionURI
    ) public virtual onlyOwner {
        _collectionURI = newCollectionURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }

    function setBaseURI(string memory newBaseUri) public onlyOwner {
        _baseUri = newBaseUri;
    }

    function getBaseURI() public view returns (string memory) {
        return _baseURI();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721CreateX, ERC2981Base) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

