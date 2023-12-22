// SPDX-LICENSE-IDENTIFIER: UNLICENSED

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./BoringERC20.sol";
import "./SimpleFactory.sol";
import "./VibeERC721.sol";
import "./IDistributor.sol";
import "./IWETH.sol";
import "./MintSaleBase.sol";

contract NFTMintSaleMultiple is Ownable, MintSaleBase {
    event Created(bytes data);
    event LogNFTBuy(address indexed recipient, uint256 tokenId, uint256 tier);
    event LogNFTBuyMultiple(address indexed recipient, uint256[] tiers);
    event SaleExtended(uint32 newEndTime);
    event SaleEnded();
    event SaleEndedEarly();
    event TokensClaimed(uint256 total, uint256 fee, address proceedRecipient);

    using BoringERC20 for IERC20;

    uint256 public constant BPS = 100_000;
    address private immutable masterNFT;

    VibeERC721 public nft;
    uint32 public beginTime;
    uint32 public endTime;

    struct TierInfo {
        uint128 price;
        uint32 beginId;
        uint32 endId;
        uint32 currentId;
    }

    TierInfo[] public tiers;
    IERC20 public paymentToken;

    SimpleFactory public immutable vibeFactory;

    struct VibeFees {
        address vibeTreasury;
        uint96 feeTake;
    }
    
    VibeFees public fees;

    constructor (address masterNFT_, SimpleFactory vibeFactory_, IWETH WETH_) MintSaleBase(WETH_) {
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

    function setVibeFees(address vibeTreasury_, uint96 feeTake_) external onlyMasterContractOwner {
        fees = VibeFees(vibeTreasury_, feeTake_);
    }

    function init(bytes calldata data) external {
        (address proxy, uint32 beginTime_, uint32 endTime_, TierInfo[] memory tiers_, IERC20 paymentToken_, address owner_) = abi.decode(data, (address, uint32, uint32, TierInfo[], IERC20, address));
        require(nft == VibeERC721(address(0)), "Already initialized");

        _transferOwnership(owner_);


        {
            (address treasury, uint96 feeTake )= NFTMintSaleMultiple(vibeFactory.masterContractOf(address(this))).fees();

            fees = VibeFees(treasury, feeTake);
        }

        nft = VibeERC721(proxy);

        {
            // circumvents UnimplementedFeatureError: Copying of type struct NFTMintSaleMultiple.TierInfo calldata[] calldata to storage not yet supported.
            for(uint256 i; i < tiers_.length; i++) {
                tiers.push(tiers_[i]);
            }
        }
        

        paymentToken = paymentToken_;
        beginTime = beginTime_;
        endTime = endTime_;

        {
            // checks parameter for correct values, can be commented out for increased gas efficiency.
            for (uint256 i = tiers_.length - 1; i > 0; i--) {
                require(tiers_[i].endId >= tiers_[i].beginId && tiers_[i-1].endId < tiers_[i].beginId, "Parameter verification failed");
            }
        }
        
        emit Created(data);
    }

    function _preBuyCheck(address recipient, uint256 tier) internal virtual {}

    function buyNFT(address recipient, uint256 tier) public payable {
        _preBuyCheck(recipient, tier);
        TierInfo memory tierInfo = tiers[tier];
        uint256 id = uint256(tierInfo.currentId);
        require(block.timestamp >= beginTime && block.timestamp <= endTime && id <= tierInfo.endId);
        getPayment(paymentToken, uint256(tierInfo.price));
        nft.mintWithId(recipient, id);
        tiers[tier].currentId++;
        emit LogNFTBuy(recipient, id, tier);
    }

    function buyMultipleNFT(address recipient, uint256[] calldata tiersToBuy) external payable {
        for (uint i; i < tiersToBuy.length; i++) {
            buyNFT(recipient, tiersToBuy[i]);
        }

        emit LogNFTBuyMultiple(recipient, tiersToBuy);
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

    function extendEndTime(uint32 newEndTime) external onlyOwner {
        require(newEndTime > block.timestamp);
        endTime = newEndTime;

        emit SaleExtended(endTime);
    }
}


