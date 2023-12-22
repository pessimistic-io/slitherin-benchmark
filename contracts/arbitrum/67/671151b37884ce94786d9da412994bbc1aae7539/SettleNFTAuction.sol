// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./BoringOwnable.sol";
import "./Domain.sol";
import "./BoringERC20.sol";
import "./IERC721.sol";

contract SettleNFTAuction is BoringOwnable, Domain {
    using BoringERC20 for IERC20;
    event LogSetAuctionSettler(address indexed settler, bool status);
    event LogFinalize(SellerParams seller, BuyerParams buyer, IERC721 nft, uint256 tokenId, IERC20 token, address settler);

    mapping (address => bool) public isSettler;

    // for signed auction sells 
    mapping(address => uint256) public noncesSeller;

    // for signed auction bids
    mapping(address => uint256) public noncesBidder;

    struct SigParams {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct BuyerParams {
        address buyer;
        uint256 bid;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct SellerParams {
        address seller;
        uint256 endTime;
        uint256 minimumBid;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    // NOTE on signature hashes: the domain separator only guarantees that the
    // chain ID and master contract are a match, so we explicitly include the
    // auction address:

    
    bytes32 private constant CREATE_SIGNATURE_HASH = keccak256("CreateAuction(address nft,uint256 tokenId,address auction,address token,uint256 endTime,uint256 minimumBid,uint256 nonce,uint256 deadline)");

    bytes32 private constant BID_SIGNATURE_HASH = keccak256("CreateBid(address nft,uint256 tokenId,address auction,address token,uint256 bid,uint256 nonce,uint256 deadline)");

    function setSettler(address settler, bool status) external onlyOwner {
        isSettler[settler] = status;
        emit LogSetAuctionSettler(settler, status);
    }

    function finalize(BuyerParams calldata buyer, SellerParams calldata seller, IERC721 nft, uint256 tokenId, IERC20 token, address settler, SigParams calldata sig) external {
        require(
                buyer.bid >= seller.minimumBid &&
                block.timestamp >= seller.endTime &&
                block.timestamp <= seller.deadline &&
                block.timestamp <= buyer.deadline &&
                settler != address(0),
                "Auction: Parameter missmatch"
            );

        {
            bytes32 sellerHash = keccak256(
            abi.encode(
                    CREATE_SIGNATURE_HASH,
                    nft,
                    tokenId,
                    address(this),
                    token,
                    seller.endTime,
                    seller.minimumBid,
                    noncesSeller[seller.seller]++,
                    seller.deadline
                )
            );
            require(ecrecover(_getDigest(sellerHash), seller.v, seller.r, seller.s) == seller.seller, "Auction: seller signature invalid");
        }
        
        {
            bytes32 buyerHash = keccak256(
            abi.encode(
                    BID_SIGNATURE_HASH,
                    nft,
                    tokenId,
                    address(this),
                    token,
                    buyer.bid,
                    noncesBidder[buyer.buyer]++,
                    buyer.deadline
                )
            );
            require(ecrecover(_getDigest(buyerHash), buyer.v, buyer.r, buyer.s) == buyer.buyer , "Auction: buyer signature invalid");

        }

        bytes32 digest = keccak256(abi.encode(buyer, seller, nft, tokenId, token));

        require(ecrecover(_getDigest(digest), sig.v, sig.r, sig.s) == settler && isSettler[settler], "Auction: settler sig invalid");

        uint256 transferAmount = buyer.bid;

        if (nft.supportsInterface(0x2a55205a)) {
            (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, transferAmount);
            transferAmount = transferAmount - royaltyAmount;
            token.safeTransferFrom(buyer.buyer, receiver, royaltyAmount);
        }

        token.safeTransferFrom(buyer.buyer, seller.seller, transferAmount);
        nft.safeTransferFrom(seller.seller, buyer.buyer, tokenId);

        emit LogFinalize(seller, buyer, nft, tokenId, token, settler);
    }

    function cancelAuction() external {
        noncesSeller[msg.sender]++;
    }

    function cancelBid() external {
        noncesBidder[msg.sender]++;
    }
}
