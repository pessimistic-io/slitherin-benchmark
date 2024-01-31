// SPDX-License-Identifier:UNLICENSED
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import "./IERC721.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ITransferProxy.sol";
import "./NFTMarketReserveAuction.sol";
import "./TradeV4.sol";

/// @title EnigmaMarket
///
/// @dev This contract is a Transparent Upgradable based in openZeppelin v3.4.0.
///         Be careful when upgrade, you must respect the same storage.

contract EnigmaMarket is
    TradeV4,
    ERC721HolderUpgradeable, // Make sure the contract is able to use its
    NFTMarketReserveAuction
{
    /// oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line
    constructor() initializer {}

    /**
     * @notice Called once to configure the contract after the initial proxy deployment.
     * @dev This farms the initialize call out to inherited contracts as needed to initialize mutable variables.
     * @param _buyerFee the fee taken from the buyer, expressed in *1000 (ej: 10% = 0.1 => 100)
     * @param _sellerFee the fee taken from the seller, expressed in *1000 (ej: 10% = 0.1 => 100)
     * @param _transferProxy the proxy from wich all NFT transfers are gonna be processed from.
     * @param _enigmaNFT721Address Enigma ERC721 NFT proxy.
     * @param _enigmaNFT1155Address Enigma ERC1155 NFT proxy.
     * @param _custodialAddress The address on wich NFTs are gonna be kept during Fiat Trades.
     * @param _minDuration The min duration for auctions, in seconds.
     * @param _maxDuration The max duration for auctions, in seconds.
     * @param _minIncrementPermille The minimum required when making an offer or placing a bid. Ej: 100 => 0.1 => 10%
     */
    function fullInitialize(
        uint8 _buyerFee,
        uint8 _sellerFee,
        ITransferProxy _transferProxy,
        address _enigmaNFT721Address,
        address _enigmaNFT1155Address,
        address _custodialAddress,
        uint256 _minDuration,
        uint256 _maxDuration,
        uint16 _minIncrementPermille
    ) external initializer {
        initializeTradeV4(
            _buyerFee,
            _sellerFee,
            _transferProxy,
            _enigmaNFT721Address,
            _enigmaNFT1155Address,
            _custodialAddress
        );
        __Ownable_init();
        __ReentrancyGuard_init();
        _initializeNFTMarketAuction();
        _initializeNFTMarketReserveAuction(_minDuration, _maxDuration);
        _initializeNFTMarketCore(_minIncrementPermille);
    }

    /**
     * @notice Called once to configure the contract after the initial proxy deployment.
     * @dev as we are updating an already deployed contracts, legacy vars don't need init.
     * @param _minDuration The min duration for auctions, in seconds.
     * @param _maxDuration The max duration for auctions, in seconds.
     */
    function upgradeInitialize(uint256 _minDuration, uint256 _maxDuration) external onlyOwner {
        _initializeNFTMarketAuction();
        _initializeNFTMarketReserveAuction(_minDuration, _maxDuration);
    }

    function getPlatformTreasury() public view returns (address payable) {
        // TODO: review if we don't need a new field for collecting fees
        return payable(owner());
    }

    /**
     * @inheritdoc NFTMarketCore
     */
    function _transferFromEscrow(
        address nftContract,
        uint256 tokenId,
        address recipient
    ) internal virtual override {
        // As we are transfering through our own market, there's no need to go by transferProxy
        IERC721(nftContract).transferFrom(address(this), recipient, tokenId);
    }

    /**
     * @inheritdoc NFTMarketCore
     */
    function _transferToEscrow(address nftContract, uint256 tokenId) internal virtual override {
        safeTransferFrom(AssetType.ERC721, msg.sender, address(this), nftContract, tokenId, 1);
    }

    /**
     * @dev Be careful when invoking this function as reentrancy guard should be put in place
     */
    // slither-disable-next-line reentrancy-eth
    function _distFunds(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        address payable seller
    )
        internal
        override
        returns (
            uint256 platformFee,
            uint256 royaltyFee,
            uint256 assetFee
        )
    {
        // Disable slither warning because it's only invoked from functions with nonReentrant checks
        Fee memory fee = getFees(amount, nftContract, tokenId);
        _sendValueWithFallbackWithdraw(getPlatformTreasury(), fee.platformFee, SEND_VALUE_GAS_LIMIT_SINGLE_RECIPIENT);
        uint256 toSeller;
        // Verifies it the seller is the creator, to avoid doble sent and save some gas
        if (seller == fee.tokenCreator) {
            toSeller = fee.royaltyFee + fee.assetFee;
        } else {
            _sendValueWithFallbackWithdraw(
                payable(fee.tokenCreator),
                fee.royaltyFee,
                SEND_VALUE_GAS_LIMIT_SINGLE_RECIPIENT
            );
            toSeller = fee.assetFee;
        }
        _sendValueWithFallbackWithdraw(seller, toSeller, SEND_VALUE_GAS_LIMIT_SINGLE_RECIPIENT);
        return (fee.platformFee, fee.royaltyFee, fee.assetFee);
    }

    /*********************
     ** PUBLIC FUNCTIONS *
     *********************/

    /**
     * @notice Creates an auction for the given NFT.
     * The NFT is held in escrow until the auction is finalized or canceled.
     * @param nftContract The address of the NFT contract.
     * @param tokenId The id of the NFT.
     * @param duration seconds for how long an auction lasts for once the first bid has been received.
     * @param reservePrice The initial reserve price for the auction.
     */
    function createReserveAuction(
        address nftContract,
        uint256 tokenId,
        uint256 duration,
        uint256 reservePrice
    ) external nonReentrant onlyValidAuctionConfig(reservePrice) {
        // get the amount, including buyer fee for this reserve price
        uint256 amount = applyBuyerFee(reservePrice, buyerFeePermille);
        createReserveAuctionFor(
            nftContract,
            tokenId,
            duration,
            reservePrice,
            amount,
            buyerFeePermille,
            sellerFeePermille
        );
    }
}

