//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import {IERC20} from "./IERC20.sol";
import {ERC721} from "./ERC721.sol";
import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {Ownable} from "./Ownable.sol";
import {Counters} from "./Counters.sol";

contract DpxBonds is ERC721("DpxBonds", "DPXB"), ERC721Enumerable, Ownable {
    // ========= Events =========== //
    event LogBootstrapped(uint256 discount, uint256 price);
    event LogUsdcDeposit(address userAddress, uint256 amount);
    event LogWithdraw(address userAddress, uint256 amount);
    event LogEmergencyWithdraw();

    using Counters for Counters.Counter;

    /// @dev Token ID counter for straddle positions
    Counters.Counter private _tokenIdCounter;

    /// @dev Max amount of USDC to deposit per dopexBridgoorNFT
    uint256 public depositPerNft = 5 * 10**6;

    /// @dev Start time for the first epoch
    uint256 public startTime;

    /// @dev USDC contract
    IERC20 public USDC;

    /// @dev DPX contract
    IERC20 public DPX;

    /// @dev DopexBridgoorNFT contract
    IERC721Enumerable public dopexBridgoorNFT;

    constructor(
        address _USDC,
        address _DPX,
        address _DopexBridgoorNFT
    ) {
        USDC = IERC20(_USDC);
        DPX = IERC20(_DPX);
        dopexBridgoorNFT = IERC721Enumerable(_DopexBridgoorNFT);
    }
    /// @dev current epoch
    uint256 public epochNumber = 0;

    /// @dev Discount for the each epoch
    mapping(uint256 => uint256) public maxDepositsPerEpoch;

    /// @dev Expiry for the each epoch
    mapping(uint256 => uint256) public epochExpiry;

    /// @dev Discount for the current epoch
    mapping(uint256 => uint256) public epochDiscount;

    /// @dev total amount of usdc deposited for each epoch
    mapping(uint256 => uint256) public totalEpochDeposits;

    /// @dev DPX price for the current epoch
    mapping(uint256 => uint256) public dpxPrice;

    /// @dev amount of usdc deposited per NFT id  for each epoch
    mapping(uint256 => mapping(uint256 => uint256)) public depositsPerNftId;

    /// @dev Bond NFTs minted for deposits
    struct BondsNft {
        uint256 epoch;
        bool redeemed;
        uint256 issued;
        uint256 maturityTime;
    }

    /// @dev Returns nftsState struct for nft id
    mapping(uint256 => BondsNft) public nftsState;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @dev get total deposits for the current epoch
    function getTotalEpochDeposits(uint256 currentEpoch)
        public
        view
        returns (uint256)
    {
        return totalEpochDeposits[currentEpoch];
    }

    /**
     * @dev Bootstrap a new epoch with a certain price and discount
     * @param discount for a new epoch
     * @param price DPX price for a new epoch, must be (price 10 ** 6)
     * @param maxEpochDeposits max USDC allowed to deposit per epoch, must be (maxEpochDeposits * 10 ** 6);
     * @param expiryTime expiry time for the epoch
     */
    function bootstrap(
        uint256 discount,
        uint256 price,
        uint256 maxEpochDeposits,
        uint256 expiryTime
    ) public onlyOwner {
        require(block.timestamp > epochExpiry[epochNumber] , "Epoch is not expired");
        require(discount > 0, "Discount can not be zero");
        require(price > 0, "Price can not be zero");
        require(maxEpochDeposits > 0, "maxEpochDeposits can not be zero");
        require(expiryTime > 0, "expiryTime can not be zero");

        if (startTime == 0) {
            startTime = block.timestamp;
        } else {
            startTime += block.timestamp;
        }

        epochNumber +=1;
        epochExpiry[epochNumber] = block.timestamp + expiryTime;

        uint256 requiredDPX = (maxEpochDeposits * 10**18) /
            ((price * (100 - discount)) / 100);

        maxDepositsPerEpoch[epochNumber] = maxEpochDeposits;
        epochDiscount[epochNumber] = discount;
        dpxPrice[epochNumber] = price;

        DPX.transferFrom(msg.sender, address(this), requiredDPX);
        emit LogBootstrapped(discount, price);
    }

    /**
     * @dev Returns an array of dopexBridgoorNFTs ids that were not used it previous deposits
     */
    function getUsableNfts(address user)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count;
        for (uint256 i = 0; i < dopexBridgoorNFT.balanceOf(user); i++) {
            if (getDepositsPerUserNftIndex(user, i) < depositPerNft) {
                count++;
            }
        }
        uint256[] memory usableNfts = new uint256[](count);
        count = 0;
        for (uint256 i = 0; i < dopexBridgoorNFT.balanceOf(user); i++) {
            if (getDepositsPerUserNftIndex(user, i) < depositPerNft) {
                usableNfts[count++] = dopexBridgoorNFT.tokenOfOwnerByIndex(
                    user,
                    i
                );
            }
        }

        return usableNfts;
    }

    /**
     * @dev Get  DPX-Bonds NFT user balance
     */
    function getDopexBondsNftBalance(address user)
        public
        view
        returns (uint256)
    {
        return this.balanceOf(user);
    }

    /**
     * @dev Allows anyone to deposit erc20(usdc) during the epoch
     * @param usableNfts Amount of nfts avaliable for deposit
     */
    function mint(uint256[] memory usableNfts) public {
        uint256 amount = usableNfts.length * depositPerNft;
        require(
            epochDiscount[epochNumber] > 0,
            "Epoch was not bootstrapped"
        );
        require(
            dopexBridgoorNFT.balanceOf(msg.sender) > 0,
            "Sender does not own NFT"
        );
        require(
            ((totalEpochDeposits[epochNumber] + amount) <=
                maxDepositsPerEpoch[epochNumber]),
            "Deposits limit reached for epoch"
        );

        for (uint256 i = 0; i < usableNfts.length; i++) {
            require(dopexBridgoorNFT.ownerOf(usableNfts[i]) == msg.sender, "Sender doesn't own NFT");
            require(depositsPerNftId[epochNumber][usableNfts[i]] == 0, "NFT already used for this epoch");

            depositsPerNftId[epochNumber][usableNfts[i]] = depositPerNft;
            uint256 mintedBondsNftId = _mint(msg.sender);
            nftsState[mintedBondsNftId] = BondsNft(
                epochNumber,
                false,
                block.timestamp,
                (block.timestamp + 7 days)
            );
        }

        totalEpochDeposits[epochNumber] += amount;
        USDC.transferFrom(msg.sender, address(this), amount);

        emit LogUsdcDeposit(msg.sender, amount);
    }

    /**
     * @dev Mints bonds nft for deposit
     */
    function _mint(address to) private returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev Checks how much USDC was deposited for an NFT
     */
    function getDepositsPerUserNftIndex(address user, uint256 index)
        public
        view
        returns (uint256)
    {
        return
            depositsPerNftId[epochNumber][
                dopexBridgoorNFT.tokenOfOwnerByIndex(user, index)
            ];
    }

    /**
     * @dev Returns an array of bonds NFT ids, that were not redeemed
     */
    function getWithdrawableNfts(address user)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count;
        for (uint256 i = 0; i < getDopexBondsNftBalance(user); i++) {
            uint256 nftId = this.tokenOfOwnerByIndex(user, i);
            if (!nftsState[nftId].redeemed) {
                count++;
            }
        }
        uint256[] memory withdrawableNfts = new uint256[](count);
        count = 0;
        for (uint256 i = 0; i < getDopexBondsNftBalance(user); i++) {
            uint256 nftId = this.tokenOfOwnerByIndex(user, i);
            if (!nftsState[nftId].redeemed) {
                withdrawableNfts[count++] = nftId;
            }
        }

        return withdrawableNfts;
    }

    /**
     * @dev Returns an array of bonds NFT ids, that were not redeemed for a selected epoch.
     */
    function getWithdrawableNftsForSelectedEpoch(address user, uint256 epoch)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count;
        for (uint256 i = 0; i < getDopexBondsNftBalance(user); i++) {
            uint256 nftId = this.tokenOfOwnerByIndex(user, i);
            if (!nftsState[nftId].redeemed && nftsState[nftId].epoch == epoch && nftsState[nftId].maturityTime <= block.timestamp ) {
                count++;
            }
        }

        uint256[] memory withdrawableNftsForSelectedEpoch = new uint256[](
            count
        );

        count = 0;
        for (uint256 i = 0; i < getDopexBondsNftBalance(user); i++) {
            uint256 nftId = this.tokenOfOwnerByIndex(user, i);
            if (!nftsState[nftId].redeemed && nftsState[nftId].epoch == epoch  && nftsState[nftId].maturityTime <= block.timestamp) {
                withdrawableNftsForSelectedEpoch[count++] = nftId;
            }
        }

        return withdrawableNftsForSelectedEpoch;
    }

    /**
     * @dev calculates how much a user can withdraw at any point in time - after the deposits have hit the limit for that epoch
     */
    function redeem(uint256 epoch) public {
        uint256[] memory withdrawableNFTs = getWithdrawableNftsForSelectedEpoch(
            msg.sender,
            epoch
        );
        require(
            getDopexBondsNftBalance(msg.sender) > 0,
            "User doesn't have a deposit"
        );
        require(withdrawableNFTs.length > 0, "User doesn't have eligible bonds");

        for (uint256 i; i < withdrawableNFTs.length; i++) {
            nftsState[withdrawableNFTs[i]].redeemed = true;
        }

        uint256 price = dpxPrice[epoch];
        uint256 discount = (price * epochDiscount[epoch]) / 100;
        uint256 priceWithDiscount = price - discount;

        uint256 amountForWithdraw = ((withdrawableNFTs.length *
            depositPerNft *
            10**18) / priceWithDiscount);

        DPX.transfer(msg.sender, amountForWithdraw);

        emit LogWithdraw(msg.sender, amountForWithdraw);
    }

    /**
     * @dev allows owner to withdraw all usdc in the contract
     */
    function emergencyWithdraw() public onlyOwner {
        USDC.transfer(msg.sender, USDC.balanceOf(address(this)));
        DPX.transfer(msg.sender, DPX.balanceOf(address(this)));
        emit LogEmergencyWithdraw();
    }
}

