// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./BoringOwnable.sol";
import "./Domain.sol";
import "./BoringERC20.sol";
import "./IERC721.sol";

contract FixedPriceSale is Domain {
    using BoringERC20 for IERC20;
    event LogFinalize(address indexed seller, uint256 endTime, uint256 price, address indexed buyer, IERC721 nft, uint256 tokenId, IERC20 token);

    // for signed auction sells 
    // nonce is not automatically updated but can be used to invalidate all current listings
    mapping(address => uint256) public noncesSeller;

    struct SellerParams {
        address seller;
        uint256 endTime;
        uint256 price;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    
    bytes32 private constant CREATE_SIGNATURE_HASH = keccak256("CreateSale(address nft,uint256 tokenId,address sale,address token,uint256 endTime,uint256 price,uint256 nonce)");

    function finalize(SellerParams calldata seller, IERC721 nft, uint256 tokenId, IERC20 token) external {
        require(
                block.timestamp >= seller.endTime,
                "Sale: Parameter missmatch"
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
                    seller.price,
                    // no increase here to allow for concurrent listings
                    noncesSeller[seller.seller]
                )
            );
            require(ecrecover(_getDigest(sellerHash), seller.v, seller.r, seller.s) == seller.seller, "Auction: seller signature invalid");
        }

        uint256 transferAmount = seller.price;

        if (nft.supportsInterface(0x2a55205a)) {
            (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, transferAmount);
            transferAmount = transferAmount - royaltyAmount;
            token.safeTransferFrom(msg.sender, receiver, royaltyAmount);
        }

        token.safeTransferFrom(msg.sender, seller.seller, transferAmount);
        nft.safeTransferFrom(seller.seller, msg.sender, tokenId);

        emit LogFinalize(seller.seller, seller.endTime, seller.price, msg.sender, nft, tokenId, token);
    }

    function cancelSale() external {
        noncesSeller[msg.sender]++;
    }
}
