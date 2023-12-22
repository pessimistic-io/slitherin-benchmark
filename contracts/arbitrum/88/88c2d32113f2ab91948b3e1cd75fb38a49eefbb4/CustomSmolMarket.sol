// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./Ownable.sol";
import "./introspection_IERC165.sol";
import "./IERC721.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";


contract CustomSmolMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // state vars

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    uint256 public constant BASIS_POINTS = 10000;

    address public paymentToken;
    uint256 public fee;
    address public feeReceipient;

    struct Listing {
        address owner;
        uint256 tokenId;
        uint256 price;
        bool listed;
        uint256 index;
    }

    //  _nftAddress => _tokenId => _owner
    mapping(address => mapping(uint256 => Listing)) public listings;

    //  _nftAddress => tokenIndex
    mapping(address => uint256[]) public tokenIndex;


    mapping(address => bool) public nftWhitelist;


    event UpdateFee(uint256 fee);
    event UpdateFeeRecipient(address feeRecipient);
    event UpdatePaymentToken(address paymentToken);

    event NftWhitelistAdd(address nft);
    event NftWhitelistRemove(address nft);

    event ItemListed(
        address seller,
        address customSmolNFT,
        uint256 tokenId,
        uint256 price
    );

    event ItemUpdated(
        address seller,
        address customSmolNFT,
        uint256 tokenId,
        uint256 price
    );

    event ItemSold(
        address seller,
        address buyer,
        address customSmolNFT,
        uint256 tokenId,
        uint256 price
    );

    event ItemCanceled(address seller, address customSmolNFT, uint256 tokenId);

    // mapping(address => mapping(uint256 => Listing)) public listings;

    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId];
        require(listing.listed == true, "not listed item");
        require(listing.owner == _owner, "not listed item");
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId];
        require(listing.listed == false, "already listed");
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listedItem = listings[_nftAddress][_tokenId];
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else {
            revert("invalid nft address");
        }
        _;
    }

    modifier onlyWhitelisted(address nft) {
        require(nftWhitelist[nft], "nft not whitelisted");
        _;
    }

    constructor(uint256 _fee, address _paymentToken) {
        setFee(_fee);
        setFeeRecipient(msg.sender);
        setPaymentToken(_paymentToken);
    }

    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price
    ) external notListed(_nftAddress, _tokenId, _msgSender()) onlyWhitelisted(_nftAddress) {

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "item not approved");
        } else {
            revert("invalid nft address");
        }

        tokenIndex[_nftAddress].push(_tokenId);

        uint256 _index = tokenIndex[_nftAddress].length-1;

        listings[_nftAddress][_tokenId] = Listing(
            _msgSender(),
            _tokenId,
            _price,
            true,
            _index
        );

        emit ItemListed(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _price
        );
    }

    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
        } else {
            revert("invalid nft address");
        }
        
        listings[_nftAddress][_tokenId].price = _price;

        emit ItemUpdated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _price
        );
    }

    function cancelListing(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _msgSender())
    {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    function _cancelListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) internal {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else {
            revert("invalid nft address");
        }

        // perform a delete while keeping index intact

        _deleteToken(_nftAddress,_tokenId);

        emit ItemCanceled(_owner, _nftAddress, _tokenId);
    }

    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        Listing memory listedItem = listings[_nftAddress][_tokenId];

        // Transfer NFT to buyer
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(_nftAddress).safeTransferFrom(_owner, _msgSender(), _tokenId);
        }

        emit ItemSold(
            _owner,
            _msgSender(),
            _nftAddress,
            _tokenId,
            listedItem.price
        );
        
        // perform a delete while keeping index intact

        _deleteToken(_nftAddress,_tokenId);

        // transfer token

        if (listedItem.price > 0) {
        _buyItem(listedItem.price,_owner);
        }
    }

    function _buyItem(
        uint256 _price,
        address _owner
    ) internal {
        uint256 totalPrice = _price;
        uint256 feeAmount = totalPrice * fee / BASIS_POINTS;
        IERC20(paymentToken).safeTransferFrom(_msgSender(), feeReceipient, feeAmount);
        IERC20(paymentToken).safeTransferFrom(_msgSender(), _owner, totalPrice - feeAmount);

    }

    // admin

    function setFee(uint256 _fee) public onlyOwner {
        require(_fee < BASIS_POINTS, "max fee");
        fee = _fee;
        emit UpdateFee(_fee);
    }

    function setFeeRecipient(address _feeRecipient) public onlyOwner {
        feeReceipient = _feeRecipient;
        emit UpdateFeeRecipient(_feeRecipient);
    }

    function setPaymentToken(address _paymentToken) public onlyOwner {
        paymentToken = _paymentToken;
        emit UpdatePaymentToken(_paymentToken);
    }

    function addToWhitelist(address _nft) external onlyOwner {
        require(!nftWhitelist[_nft], "nft already whitelisted");
        nftWhitelist[_nft] = true;
        emit NftWhitelistAdd(_nft);
    }

    function removeFromWhitelist(address _nft) external onlyOwner onlyWhitelisted(_nft) {
        nftWhitelist[_nft] = false;
        emit NftWhitelistRemove(_nft);
    }


    function nftTokenListed(address _nftAddress, uint256 _tokenId) public view returns(bool isIndeed) {
    if(tokenIndex[_nftAddress].length == 0) return false;
    return (tokenIndex[_nftAddress][listings[_nftAddress][_tokenId].index] == _tokenId);
    }

    function getNftTokenCount(address _nftAddress) public view returns(uint count) {
    return tokenIndex[_nftAddress].length;
    }

    function getNftTokenAtIndex(address _nftAddress, uint _index) public view returns(uint256)
    {
    return tokenIndex[_nftAddress][_index];
    }

    function _deleteToken(address _nftAddress, uint256 _tokenId) internal {


        // get the index row of the token to delete

        Listing storage listing = listings[_nftAddress][_tokenId];

        uint256 rowToDelete = listing.index;


        // move the token in that last row of the index to the row we are deleting, this overwrites / deletes the token from the index
        
        uint256 keyToMove = tokenIndex[_nftAddress].length-1;


        uint256 valueToUpdate = tokenIndex[_nftAddress][keyToMove];

        tokenIndex[_nftAddress][rowToDelete] = valueToUpdate;


        // update the moved tokens mapped index in the Struct

        Listing storage movedToken = listings[_nftAddress][valueToUpdate];
        movedToken.index = rowToDelete;

        // delete the last row of the index to update index.length

        tokenIndex[_nftAddress].pop();

        // finally delete the listing from the mapping

        delete (listings[_nftAddress][_tokenId]);

    }

    function fetchNftTokens(address _nftAddress, uint256 _tokenId) public view returns (uint256 tokenId, address owner, uint256 price, bool listed) {
    
    uint256 nftTokenId = listings[_nftAddress][_tokenId].tokenId;
    address nftOwner = listings[_nftAddress][_tokenId].owner;
    uint256 nftTokenPrice = listings[_nftAddress][_tokenId].price;
    bool tokenListed = listings[_nftAddress][_tokenId].listed; 

    return (nftTokenId, nftOwner, nftTokenPrice, tokenListed);
    } 
}
