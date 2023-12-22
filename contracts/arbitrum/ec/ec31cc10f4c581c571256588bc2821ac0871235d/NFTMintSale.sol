// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./BoringERC20.sol";
import "./BoringFactory.sol";
import "./MintSaleBase.sol";

/// @title NFTMintSale
/// @notice A contract for minting and selling NFTs during a limited time period.
/// @author @Clearwood 
contract NFTMintSale is Ownable, MintSaleBase {
    using BoringERC20 for IERC20;
    
    uint64 public maxMint;
    uint128 public price;
    
    event Created(bytes data);
    event LogNFTBuy(address indexed recipient, uint256 tokenId);


    /// @notice Initializes the NFTMintSale contract with the masterNFT address and the vibeFactory address.
    /// @param masterNFT_ The address of the master NFT.
    /// @param vibeFactory_ The address of the SimpleFactory contract.
    /// @param WETH_ The address of the WETH contract
    constructor (address masterNFT_, SimpleFactory vibeFactory_, IWETH WETH_)  MintSaleBase(masterNFT_, vibeFactory_, WETH_) {
    }

    /// @notice Initializes the NFTMintSale with the provided data.
    /// @param data The initialization data in bytes.
    function init(bytes calldata data) public payable {
        (address proxy, uint64 maxMint_, uint32 beginTime_, uint32 endTime_, uint128 price_, IERC20 paymentToken_, address owner_) = abi.decode(data, (address, uint64, uint32, uint32, uint128, IERC20, address));
        
        require(nft == VibeERC721(address(0)), "Already initialized");

        _transferOwnership(owner_);

        {
            (address treasury, uint96 feeTake )= NFTMintSale(vibeFactory.masterContractOf(address(this))).fees();

            fees = VibeFees(treasury, feeTake);
        }

        nft = VibeERC721(proxy);

        maxMint = maxMint_;
        price = price_;
        paymentToken = paymentToken_;
        beginTime = beginTime_;
        endTime = endTime_;

        emit Created(data);
    }

    function _preBuyCheck(address recipient) internal virtual {}

    function _buyNFT(address recipient) internal {
        _preBuyCheck(recipient);
        require(block.timestamp >= beginTime && block.timestamp <= endTime && nft.totalSupply() < maxMint);
        uint256 tokenId = nft.mint(recipient);
        emit LogNFTBuy(recipient, tokenId);
    }

    /// @notice Buys a single NFT for the specified recipient.
    /// @dev The payment token must be approved before calling this function.
    /// @param recipient The address of the recipient who will receive the NFT.
    function buyNFT(address recipient) public payable {
        _buyNFT(recipient);
        getPayment(paymentToken, price);
    }

    /// @notice Buys multiple NFTs for the specified recipient.
    /// @dev The payment token must be approved before calling this function.
    /// @param recipient The address of the recipient who will receive the NFTs.
    /// @param number The number of NFTs to buy.
    function buyMultipleNFT(address recipient, uint256 number) public payable {
        for (uint i; i < number; i++) {
            _buyNFT(recipient);
        }
        getPayment(paymentToken, price * number);
    }

}

