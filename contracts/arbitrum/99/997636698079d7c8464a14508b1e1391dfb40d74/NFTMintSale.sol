// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./BoringERC20.sol";
import "./BoringFactory.sol";
import "./SimpleFactory.sol";
import "./VibeERC721.sol";
import "./IDistributor.sol";
import "./IWETH.sol";
import "./MintSaleBase.sol";

/// @title NFTMintSale
/// @notice A contract for minting and selling NFTs during a limited time period.
/// @author @Clearwood 
contract NFTMintSale is Ownable, MintSaleBase {
    using BoringERC20 for IERC20;
    uint256 public constant BPS = 100_000;
    address private immutable masterNFT;

    VibeERC721 public nft;
    SimpleFactory public immutable vibeFactory;
    uint64 public maxMint;
    uint32 public beginTime;
    uint32 public endTime;
    uint128 public price;
    IERC20 public paymentToken;
    
    event Created(bytes data);
    event LogNFTBuy(address indexed recipient, uint256 tokenId);
    event SaleExtended(uint32 newEndTime);
    event SaleEnded();
    event SaleEndedEarly();
    event TokensClaimed(uint256 total, uint256 fee, address proceedRecipient);

    struct VibeFees {
        address vibeTreasury;
        uint96 feeTake;
    }

    VibeFees public fees;

    /// @notice Initializes the NFTMintSale contract with the masterNFT address and the vibeFactory address.
    /// @param masterNFT_ The address of the master NFT.
    /// @param vibeFactory_ The address of the SimpleFactory contract.
    /// @param WETH_ The address of the WETH contract
    constructor (address masterNFT_, SimpleFactory vibeFactory_, IWETH WETH_)  MintSaleBase(WETH_) {
        masterNFT = masterNFT_;
        vibeFactory = vibeFactory_;
    }

    modifier onlyMasterContractOwner {
        address master = vibeFactory.masterContractOf(address(this));
        if (master != address(0)) {
            require(Ownable(master).owner() == msg.sender);
        }
        _;
    }

    /// @notice Sets the VibeFees for the contract.
    /// @param vibeTreasury_ The address of the Vibe treasury.
    /// @param feeTake_ The fee percentage in basis points.
    function setVibeFees(address vibeTreasury_, uint96 feeTake_) external onlyMasterContractOwner {
        fees = VibeFees(vibeTreasury_, feeTake_);
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

    function claimEarnings(address proceedRecipient) public onlyOwner {
        uint256 total = paymentToken.balanceOf(address(this));
        uint256 fee = total * uint256(fees.feeTake) / BPS;
        paymentToken.safeTransfer(proceedRecipient, total - fee);
        paymentToken.safeTransfer(fees.vibeTreasury, fee);

        if (proceedRecipient.code.length > 0) {
            (bool success, bytes memory result) = proceedRecipient.call(abi.encodeWithSignature("supportsInterface(bytes4)", type(IDistributor).interfaceId));
            if (success) {
                (bool distribute) = abi.decode(result, (bool));
                if (distribute) {
                    IDistributor(proceedRecipient).distribute(paymentToken, total - fee);
                }
            }
        }

        emit TokensClaimed(total, fee, proceedRecipient);
    }

    /// @notice Removes tokens and reclaims ownership of the NFT contract after the sale has ended.
    /// @dev The sale must have ended before calling this function.
    /// @param proceedRecipient The address that will receive the proceeds from the sale.
    function removeTokensAndReclaimOwnership(address proceedRecipient) external onlyOwner {
        if(block.timestamp < endTime){
            endTime = uint32(block.timestamp);
            emit SaleEndedEarly();
        } else {
            emit SaleEnded();
        }
        claimEarnings(proceedRecipient);
        nft.renounceMinter();
    }

    /// @notice Extends the sale end time to a new timestamp.
    /// @dev The new end time must be in the future.
    /// @param newEndTime The new end time for the sale.
    function extendEndTime(uint32 newEndTime) external onlyOwner {
        require(newEndTime > block.timestamp);
        endTime = newEndTime;

        emit SaleExtended(endTime);
    }

}

