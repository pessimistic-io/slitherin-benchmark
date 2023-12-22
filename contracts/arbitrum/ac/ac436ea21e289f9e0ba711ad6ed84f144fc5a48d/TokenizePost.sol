// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./ERC721EnumerableUpgradeable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Type.sol";
import "./Price.sol";
import "./ITokenizePost.sol";
import "./IPriceFeed.sol";
import "./ITokenizePost.sol";

contract TokenizePost is
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ITokenizePost
{
    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for int256;
    uint256 public tokenId;

    address public owner;

    // token accept to pay => price feed chain link
    mapping(address => IPriceFeed) public tokenPayToPriceFeed;

    // postId => Post
    mapping(string => Post) public override posts;

    // postId => buyers
    mapping(string => address[]) internal _buyersByPostId;

    // owner => array post id
    mapping(address => string[]) public postsByOwner;

    // tokenId => postId
    mapping(uint256 => string) public tokenIdToPostId;

    address public destinationProtocolFee;
    uint256 public protocolFeeFixedPrice;
    uint256 public protocolFeeFloorPrice;
    uint256 public holderFeeFloorPrice;
    uint256 public minPrice;

    // postId => latest buyer
    mapping(string => address[]) public postIdToLatestBuyers;

    mapping(uint256 => uint256) public indexToFeeHolderFloorPrice;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function initialize() external initializer {
        __ERC721_init("Tokenize Post", "TP");
        __ReentrancyGuard_init();
        __Pausable_init();

        tokenId = 1_000_000;
        owner = msg.sender;
        destinationProtocolFee = msg.sender;

        protocolFeeFixedPrice = 2_000;
        protocolFeeFloorPrice = 1_500;
        holderFeeFloorPrice = 1_500;

        indexToFeeHolderFloorPrice[0] = 5_000;
        indexToFeeHolderFloorPrice[1] = 3_000;
        indexToFeeHolderFloorPrice[2] = 2_000;

        minPrice = 10 ** 17;
    }

    function publishPost(
        Type.PostPrice typePrice,
        uint256 sellPrice,
        string memory postId
    ) external override nonReentrant whenNotPaused {
        address owner = msg.sender;
        require(sellPrice >= minPrice, "InitPrice not less than minPrice");
        require(posts[postId].tokenId == 0, "Post id already exists");

        uint256 tokenId = mintPost(postId, owner, uint8(typePrice));
        posts[postId] = Post({
            tokenId: tokenId,
            owner: owner,
            postId: postId,
            typePrice: uint8(typePrice),
            sellPrice: sellPrice,
            timePublish: uint64(block.timestamp),
            postSupply: 0,
            status: 0
        });
        postsByOwner[owner].push(postId);
        emit PostPublished(
            owner,
            typePrice,
            sellPrice,
            postId,
            tokenId,
            uint64(block.timestamp)
        );
    }

    function buyPost(
        string memory postId,
        address tokenPay
    ) external payable nonReentrant whenNotPaused returns (uint256 priceInUsd) {
        address buyer = msg.sender;
        uint256 amount = msg.value;
        Post memory _post = posts[postId];
        require(_post.tokenId != 0, "Post is not published");
        require(
            _post.status == uint8(Type.PostStatus.Open),
            "Post is not open"
        );
        priceInUsd = getPricePost(postId);
        uint256 tokenDecimals = Price.PRICE_PRECISION;
        uint256 tokenPrice = getPriceFeed(tokenPay);
        if (tokenPay == Type.NATIVE_ADDRESS) {
            require(
                amount.mul(tokenPrice).div(Price.PRICE_PRECISION) >= priceInUsd,
                "amount is not enough"
            );
            amount = priceInUsd.mul(Price.PRICE_PRECISION).div(tokenPrice);
        } else {
            require(
                address(tokenPayToPriceFeed[tokenPay]) != address(0x0),
                "tokenPay is not support"
            );
            tokenDecimals = 10 ** ERC20(tokenPay).decimals();
            amount = priceInUsd.mul(tokenDecimals).div(tokenPrice);
            IERC20(tokenPay).transferFrom(buyer, address(this), amount);
        }
        payFeeBuyPost(
            buyer,
            tokenPay,
            amount,
            tokenPrice,
            _post,
            tokenDecimals
        );

        if (Type.PostPrice(_post.typePrice) == Type.PostPrice.FloorPrice) {
            if (_buyersByPostId[postId].length == 0) {
                _buyersByPostId[postId].push(buyer);
            } else {
                _buyersByPostId[postId][0] = buyer;
            }
        } else {
            _buyersByPostId[postId].push(buyer);
        }
        posts[postId].postSupply++;

        emit PostBought(
            _post.owner,
            buyer,
            Type.PostPrice(_post.typePrice),
            _post.postId,
            tokenPay,
            (amount * Price.PRICE_PRECISION) / tokenDecimals,
            priceInUsd,
            uint64(block.timestamp),
            uint8(_post.postSupply + 1),
            _post.tokenId
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721EnumerableUpgradeable) {
        //        super._beforeTokenTransfer(from, to, tokenId, batchSize);

        if (from == address(0) || to == address(0)) {
            return;
        }
        require(
            from == address(this) || to == address(this),
            "Transfer is not allow"
        );
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable) {
        //solhint-disable-next-line max-line-length
        _transfer(from, to, tokenId);
    }

    function changePrice(
        string memory postId,
        uint256 newPrice
    ) public override nonReentrant whenNotPaused {
        address ownerOfPost = msg.sender;
        require(posts[postId].owner == ownerOfPost, "Not owner of post");
        require(
            Type.PostPrice(posts[postId].typePrice) ==
                Type.PostPrice.FixedPrice,
            "Must fixed price post"
        );
        require(newPrice >= minPrice, "New price not less than minPrice");

        posts[postId].sellPrice = newPrice;

        emit PriceChanged(
            ownerOfPost,
            postId,
            newPrice,
            uint64(block.timestamp)
        );
    }

    function updatePostStatus(
        string memory postId,
        Type.PostStatus status
    ) external nonReentrant whenNotPaused {
        address ownerOfPost;
        if (postIdToLatestBuyers[postId].length == 0) {
            ownerOfPost = posts[postId].owner;
        } else {
            ownerOfPost = postIdToLatestBuyers[postId][0];
        }
        require(msg.sender == ownerOfPost, "Not owner of post");
        posts[postId].status = uint8(status);

        emit PostStatusUpdated(
            ownerOfPost,
            postId,
            status,
            uint64(block.timestamp)
        );
    }

    function getPostWithHoldersByPostId(
        string memory postId
    ) public view returns (ITokenizePost.Post memory, address[] memory) {
        return (posts[postId], _buyersByPostId[postId]);
    }

    function getPostWithHoldersByTokenId(
        uint256 tokenId
    ) public view returns (ITokenizePost.Post memory, address[] memory) {
        string memory postId = tokenIdToPostId[tokenId];
        return (posts[postId], _buyersByPostId[postId]);
    }

    function getFeePercentFloorPrice(
        string memory postId,
        address buyer
    ) public view returns (uint256) {
        uint256 holderFeePercent = 0;
        address[] memory lastBuyers = postIdToLatestBuyers[postId];
        for (uint256 i = 0; i < lastBuyers.length; i++) {
            if (lastBuyers[i] == buyer) {
                holderFeePercent =
                    holderFeePercent +
                    indexToFeeHolderFloorPrice[i];
            }
        }
        return
            holderFeeFloorPrice.mul(holderFeePercent).div(Type.BASIC_POINT_FEE);
    }

    function getPricePost(string memory postId) public view returns (uint256) {
        Post memory _post = posts[postId];
        if (Type.PostPrice(_post.typePrice) == Type.PostPrice.FloorPrice) {
            if (_post.postSupply == 0) {
                return _post.sellPrice;
            }
            return Price.getPrice(_post.sellPrice, _post.postSupply);
        }
        return _post.sellPrice;
    }

    function getPriceFeed(
        address _tokenPay
    ) public view returns (uint256 price) {
        price = uint256(tokenPayToPriceFeed[_tokenPay].latestAnswer())
            .mul(Price.PRICE_PRECISION)
            .div(10 ** tokenPayToPriceFeed[_tokenPay].decimals());
    }

    function estimatePriceETH(
        string memory postId
    ) public view returns (uint256 amountETH) {
        uint256 priceInUsd = getPricePost(postId);
        uint256 price = getPriceFeed(
            0x0000000000000000000000000000000000000001
        );
        amountETH = priceInUsd.mul(Price.PRICE_PRECISION).div(price);
    }

    function _estimatePriceETH(
        uint256 priceInUsd,
        uint256 decimals
    ) internal view returns (uint256 amountETH) {
        uint256 price = getPriceFeed(
            address(0x0000000000000000000000000000000000000001)
        );
        amountETH = priceInUsd.mul(Price.PRICE_PRECISION).div(price);
    }

    function getBuyerByPostId(
        string memory postId
    ) external view returns (address[] memory) {
        return _buyersByPostId[postId];
    }

    function mintPost(
        string memory postId,
        address receiver,
        uint8 typePrice
    ) internal returns (uint256) {
        uint256 _tokenId = tokenId + 1;
        _mint(receiver, _tokenId);
        if (Type.PostPrice.FixedPrice == Type.PostPrice(typePrice)) {
            if (_buyersByPostId[postId].length == 0) {
                _buyersByPostId[postId].push(receiver);
            } else {
                _buyersByPostId[postId][0] = receiver;
            }
            posts[postId].postSupply++;
        } else {
            postIdToLatestBuyers[postId].push(receiver);
        }
        tokenIdToPostId[_tokenId] = postId;
        tokenId = _tokenId;
        return _tokenId;
    }

    function takePost(
        uint256 _tokenId,
        address _receiver,
        string memory _postId
    ) internal {
        //        address holder = _buyersByPostId[_postId][0];
        //        transferFrom(holder, address(this), _tokenId);
        //        transferFrom(address(this), _receiver, _tokenId);
        _buyersByPostId[_postId][0] = _receiver;
    }

    function payFeeBuyPost(
        address buyer,
        address tokenPay,
        uint256 amount,
        uint256 tokenPrice,
        ITokenizePost.Post memory _post,
        uint256 tokenDecimals
    ) internal {
        if (Type.PostPrice(_post.typePrice) == Type.PostPrice.FloorPrice) {
            _payFeeFloorPrice(
                tokenPay,
                amount,
                tokenPrice,
                _post,
                tokenDecimals
            );
            setBuyerFloorPrice(buyer, _post.postId);
        } else {
            _payFeeFixedPrice(
                tokenPay,
                amount,
                tokenPrice,
                _post,
                tokenDecimals
            );
        }
    }

    function setBuyerFloorPrice(address buyer, string memory postId) internal {
        address[] memory lastBuyers = postIdToLatestBuyers[postId];
        if (lastBuyers.length > 2) {
            postIdToLatestBuyers[postId][0] = buyer;
            postIdToLatestBuyers[postId][1] = lastBuyers[0];
            postIdToLatestBuyers[postId][2] = lastBuyers[1];
        } else if (lastBuyers.length > 1) {
            postIdToLatestBuyers[postId][0] = buyer;
            postIdToLatestBuyers[postId][1] = lastBuyers[0];
            postIdToLatestBuyers[postId].push(lastBuyers[1]);
        } else if (lastBuyers.length > 0) {
            postIdToLatestBuyers[postId][0] = buyer;
            postIdToLatestBuyers[postId].push(lastBuyers[0]);
        } else {
            postIdToLatestBuyers[postId].push(buyer);
        }
    }

    function transferOut(
        address tokenPay,
        address receiver,
        uint256 amount
    ) internal {
        if (tokenPay == address(0x0000000000000000000000000000000000000001)) {
            payable(receiver).transfer(amount);
        } else {
            IERC20(tokenPay).transfer(receiver, amount);
        }
    }

    function _payFeeFixedPrice(
        address tokenPay,
        uint256 amount,
        uint256 tokenPrice,
        ITokenizePost.Post memory _post,
        uint256 tokenDecimals
    ) internal {
        ITokenizePost.Fee[5] memory fees;
        uint256 protocolFee = amount.mul(protocolFeeFixedPrice).div(
            Type.BASIC_POINT_FEE
        );
        fees[0] = Fee({
            receiver: destinationProtocolFee,
            typeFee: Type.TypeFee.Protocol,
            feeInToken: covertToTokenDecimals18(protocolFee, tokenDecimals),
            feeInUsd: tokenPrice.mul(protocolFee).div(tokenDecimals)
        });
        fees[1] = Fee({
            receiver: _post.owner,
            typeFee: Type.TypeFee.Owner,
            feeInToken: covertToTokenDecimals18(
                amount - protocolFee,
                tokenDecimals
            ),
            feeInUsd: tokenPrice.mul(amount - protocolFee).div(tokenDecimals)
        });
        transferOut(tokenPay, destinationProtocolFee, protocolFee);
        transferOut(tokenPay, _post.owner, amount - protocolFee);

        emit FeePaid(
            msg.sender,
            tokenPay,
            _post.postId,
            fees,
            uint64(block.timestamp)
        );
    }

    function covertToTokenDecimals18(
        uint256 amount,
        uint256 tokenDecimals
    ) internal pure returns (uint256) {
        return amount.mul(Price.PRICE_PRECISION).div(tokenDecimals);
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        Post memory _post = posts[tokenIdToPostId[tokenId]];

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, _post.postId))
                : "";
    }

    function _payFeeFloorPrice(
        address tokenPay,
        uint256 amount,
        uint256 tokenPrice,
        ITokenizePost.Post memory _post,
        uint256 tokenDecimals
    ) internal {
        address[] memory latestBuyers = postIdToLatestBuyers[_post.postId];
        ITokenizePost.Fee[5] memory fees;
        uint256 protocolFee = amount.mul(protocolFeeFloorPrice).div(
            Type.BASIC_POINT_FEE
        );
        uint256 holderFee = amount.mul(holderFeeFloorPrice).div(
            Type.BASIC_POINT_FEE
        );
        uint256 remainHolderFee = holderFee;
        for (uint256 i = 0; i < latestBuyers.length; i++) {
            if (i == 2) {
                transferOut(tokenPay, latestBuyers[i], remainHolderFee);
                fees[i] = Fee({
                    receiver: latestBuyers[i],
                    typeFee: Type.TypeFee.Holder,
                    feeInToken: covertToTokenDecimals18(
                        remainHolderFee,
                        tokenDecimals
                    ),
                    feeInUsd: tokenPrice.mul(remainHolderFee).div(tokenDecimals)
                });
                remainHolderFee = 0;
                break;
            }
            uint feeInToken = holderFee.mul(indexToFeeHolderFloorPrice[i]).div(
                Type.BASIC_POINT_FEE
            );
            transferOut(tokenPay, latestBuyers[i], feeInToken);
            remainHolderFee -= feeInToken;
            fees[i] = Fee({
                receiver: latestBuyers[i],
                typeFee: Type.TypeFee.Holder,
                feeInToken: covertToTokenDecimals18(feeInToken, tokenDecimals),
                feeInUsd: tokenPrice.mul(feeInToken).div(tokenDecimals)
            });
        }
        /// In case not enough holder to 3 user, protocolFee will get remain holder fee
        transferOut(
            tokenPay,
            destinationProtocolFee,
            protocolFee + remainHolderFee
        );
        fees[3] = Fee({
            receiver: destinationProtocolFee,
            typeFee: Type.TypeFee.Protocol,
            feeInToken: covertToTokenDecimals18(
                protocolFee + remainHolderFee,
                tokenDecimals
            ),
            feeInUsd: tokenPrice.mul(protocolFee + remainHolderFee).div(
                tokenDecimals
            )
        });

        transferOut(tokenPay, _post.owner, amount - protocolFee - holderFee);
        fees[4] = Fee({
            receiver: _post.owner,
            typeFee: Type.TypeFee.Owner,
            feeInToken: covertToTokenDecimals18(
                amount - protocolFee - holderFee,
                tokenDecimals
            ),
            feeInUsd: tokenPrice.mul(amount - protocolFee - holderFee).div(
                tokenDecimals
            )
        });

        emit FeePaid(
            msg.sender,
            tokenPay,
            _post.postId,
            fees,
            uint64(block.timestamp)
        );
    }

    function _baseURI()
        internal
        view
        override(ERC721Upgradeable)
        returns (string memory)
    {
        return "https://post.tech/tweet/";
    }

    function setConfigFeeHolderForHolderFloorPrice(
        uint256 index,
        uint256 holderFee
    ) external onlyOwner {
        indexToFeeHolderFloorPrice[index] = holderFee;
    }

    function setHolderFeeFloorPrice(uint256 _holderFee) external onlyOwner {
        holderFeeFloorPrice = _holderFee;
    }

    function setProtocolFeeFixedPrice(uint256 _protocolFee) external onlyOwner {
        protocolFeeFixedPrice = _protocolFee;
    }

    function setProtocolFeeFloorPrice(uint256 _protocolFee) external onlyOwner {
        protocolFeeFloorPrice = _protocolFee;
    }

    function updateTokenPayToPriceFeed(
        address _tokenPay,
        address _priceFeed
    ) external onlyOwner {
        tokenPayToPriceFeed[_tokenPay] = IPriceFeed(_priceFeed);
    }

    function setDestinationProtocolFee(
        address _destinationProtocolFee
    ) external onlyOwner {
        destinationProtocolFee = _destinationProtocolFee;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}

