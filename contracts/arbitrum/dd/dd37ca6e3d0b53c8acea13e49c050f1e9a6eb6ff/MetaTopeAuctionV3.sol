//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC1155.sol";
import "./MetaTopeIERC1155Receiver.sol";

// Sanctions Contract
interface SanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}

/**
 * @title Contract for MetaTope Auction V3
 * Copyright 2022 MetaTope
 */
contract MetaTopeAuctionV3 is MetaTopeIERC1155Receiver, Ownable {
    address public sanctionsContract;

    ERC1155 public rewardToken;
    uint128 public rewardTokenId;

    struct AuctionBid {
        uint256 tokenAmount;
        uint256 pricePerToken;
        uint256 totalPrice;
        uint128 createdAt;
        bool canceled;
        bool claimed;
        ERC20 depositToken;
    }

    struct WinAuctionBid {
        uint256 tokenAmount;
        uint256 pricePerToken;
        uint256 totalPrice;
        bool claimed;
        address bidderAddress;
        ERC20 depositToken;
    }

    struct DepositToken {
        uint256 minPricePerToken;
        uint256 lowestPrice;
    }

    mapping(address => AuctionBid) public bidders;
    mapping(address => WinAuctionBid) public winners;

    mapping(ERC20 => DepositToken) public availableDepositTokenPrices;
    address[] public availableDepositTokens;

    WinAuctionBid[] public sortedBids;
    address[] public bidderAddresses;
    address[] public winnerAddresses;
    address public withdrawAddress;

    bool public started;
    bool public winnersComputed;
    bool public tokensTransferred;
    bool public bidsSorted;
    bool public lowestPricesSet;

    uint128 public startAt;
    uint128 public endAt;
    uint256 public totalTokenAmount;
    uint256 public maxTokenPerAddress;
    uint256 public computedIndex;
    uint256 public transferredIndex;
    uint256 public sortedIndex = 0;
    uint256 public totalTokenWon;

    event StartAuction();
    event MakeBid(
        address indexed user,
        uint256 tokenAmount,
        uint256 pricePerToken,
        uint256 totalPrice,
        uint128 createdAt,
        ERC20 depositToken
    );
    event UpdateBid(
        address indexed user,
        uint256 tokenAmount,
        uint256 pricePerToken,
        uint256 totalPrice,
        uint128 updatedAt,
        ERC20 depositToken
    );
    event CancelBid(address indexed user);
    event EndAuction();
    event Withdraw(address to);
    event TokensTransferred();
    event WinnersComputed();

    modifier onlyStarted() {
        require(started == true, "Auction should not be ended");
        require(endAt >= block.timestamp, "Auction was already ended");
        _;
    }

    modifier onlyEnded() {
        require(started == false, "Auction should be ended");
        _;
    }

    modifier notContract() {
        require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "Contract not allowed");
        _;
    }

    /**
     * @dev Constructor
     * @param _rewardToken reward token after auction finished
     * @param _rewardTokenId reward token id by default 0
     * @param _withdrawAddress address to withdraw to
     */
    constructor(
        ERC1155 _rewardToken,
        uint128 _rewardTokenId,
        address _withdrawAddress
    ) {
        rewardToken = _rewardToken;
        rewardTokenId = _rewardTokenId; // 0
        withdrawAddress = _withdrawAddress;
    }

    /**
     * @dev Function to start auction
     * @param _totalTokenAmount set totalTokenAmount
     * @param _endDuration set auction duration
     * @param _maxTokenPerAddress set max amountof tokens
     */
    function start(
        uint256 _totalTokenAmount,
        uint128 _endDuration,
        uint256 _maxTokenPerAddress
    ) external onlyOwner {
        require(started == false, "Auction should not be started yet");
        require(endAt == 0, "Auction cannot be restarted");
        require(
            _totalTokenAmount > 0,
            "TotalTokenAmount should be greater than zero"
        );

        totalTokenAmount = _totalTokenAmount;
        maxTokenPerAddress = _maxTokenPerAddress;
        started = true;
        startAt = uint128(block.timestamp);
        endAt = startAt + (_endDuration * 1 days);

        rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            rewardTokenId,
            totalTokenAmount,
            ""
        );

        emit StartAuction();
    }

    /**
     * @dev Function to set available deposit tokens
     * @param _token set token
     * @param _minPricePerToken set min price for the token
     */
    function setDepositTokenMinPrice(
        ERC20 _token,
        uint256 _minPricePerToken
    ) external onlyOwner {
        require(_minPricePerToken >= 0, "MinPrice should be greater/equal zero");

        availableDepositTokenPrices[_token].minPricePerToken = _minPricePerToken;

        bool tokenAlreadyPresent = depositTokenExists(address(_token));

        if(!tokenAlreadyPresent) availableDepositTokens.push(address(_token));
    }

    /**
     * @dev Function to set available deposit tokens
     * @param _token set token
     * @param _lowestPrice set lowest price for the token
     */
    function setDepositTokenLowestPrice(
        ERC20 _token,
        uint256 _lowestPrice
    ) external onlyOwner onlyEnded {
        require(_lowestPrice > 0, "LowestPrice should be greater than zero");
        require(depositTokenExists(address(_token)), "Token must be available before can set lowest price");

        availableDepositTokenPrices[_token].lowestPrice = _lowestPrice;
    }

    /**
     * @dev Function to set available deposit tokens
     */
    function setIsLowestPricesSet() external onlyOwner onlyEnded {
        for (uint256 i = 0; i < availableDepositTokens.length; ++i) {
            require(availableDepositTokenPrices[ERC20(availableDepositTokens[i])].lowestPrice > 0, "All lowest prices should be set");
        }
        lowestPricesSet = true;
    }

    /**
     * @dev Function to set chainlink sanctions contract address
     * @param _address set merkleRoot
     */
    function setSanctionContract(address _address) external {
        sanctionsContract = _address;
    }

    /**
     * @dev Function to bid or update. Called by the user
     * @param _tokenAmount Token Amount
     * @param _pricePerToken Price Per Token
     */
    function bid(uint256 _tokenAmount, uint256 _pricePerToken, ERC20 _depositToken)
        external
        onlyStarted
        notContract
    {
        SanctionsList sanctionsList = SanctionsList(sanctionsContract);
        bool isSanctioned = sanctionsList.isSanctioned(msg.sender);
        require(!isSanctioned, "Sanctioned address");

        require(_tokenAmount > 0, "TokenAmount should be greater than zero");
        require(availableDepositTokenPrices[_depositToken].minPricePerToken > 0, "Token not available");
        require(maxTokenPerAddress >= _tokenAmount, "TokenAmount should be less than maxTokenPerAddress");
        require(
            _pricePerToken >= availableDepositTokenPrices[_depositToken].minPricePerToken,
            "PricePerToken should be greater than minPricePerToken"
        );
        uint256 _approvedAmount = _depositToken.allowance(
            msg.sender,
            address(this)
        );
        uint256 _totalPrice = _pricePerToken * _tokenAmount;

        require(
            _approvedAmount >= _totalPrice,
            "ApprovedAmount should be greater than totalPrice"
        );

        uint256 oldPrice = bidders[msg.sender].totalPrice;

        // If user does not have old bid
        if (oldPrice == 0) {
            require(_depositToken.transferFrom(msg.sender, address(this), _totalPrice), "Token not transferred from user");
        } else {
            // If user had done a bid with same deposit token
            if (bidders[msg.sender].depositToken == _depositToken) {
                int256 priceBalance = int256(bidders[msg.sender].totalPrice) - int256(_totalPrice);

                if (priceBalance < 0) {
                    // User needs more token, user needs to pay addtional
                    require(_depositToken.transferFrom(msg.sender, address(this), uint256(abs(priceBalance))), "Token not transferred from user");
                } else if (priceBalance > 0) {
                    // User needs less token, we need to pay user
                    require(bidders[msg.sender].depositToken.transfer(msg.sender, uint256(priceBalance)), "Token not transferred to user");
                }
            } else {
                require(bidders[msg.sender].depositToken.transfer(msg.sender, _totalPrice), "Token not transferred to user");
                require(_depositToken.transferFrom(msg.sender, address(this), _totalPrice), "Token not transferred from user");
            }
        }

        AuctionBid memory auction = AuctionBid({
            tokenAmount: _tokenAmount,
            totalPrice: _totalPrice,
            pricePerToken: _pricePerToken,
            createdAt: uint128(block.timestamp),
            canceled: false,
            claimed: false,
            depositToken: _depositToken
        });
        uint256 oldTokenAmount = bidders[msg.sender].tokenAmount;
        bidders[msg.sender] = auction;
        if (oldTokenAmount == 0) {
            bidderAddresses.push(msg.sender);
            emit MakeBid(
                msg.sender,
                _tokenAmount,
                _pricePerToken,
                _totalPrice,
                auction.createdAt,
                _depositToken
            );
        } else {
            emit UpdateBid(
                msg.sender,
                _tokenAmount,
                _pricePerToken,
                _totalPrice,
                auction.createdAt,
                _depositToken
            );
        }
    }

    /**
     * @dev Function to get bidder addresses in chunks
     */
    function getBidderAddresses(uint256 _from, uint256 _count) external view returns(address[] memory) {
        uint256 from = _from;
        uint256 range = _from + _count;
        uint256 index = 0;
        address[] memory mBidders = new address[](range);
        for (from; from < range; ++from) {
            if (from >= bidderAddresses.length) break;
            mBidders[index] = bidderAddresses[from];
            index++;
        }
        return mBidders;
    }

    /**
     * @dev Function to get winner addresses in chunks
     */
    function getWinnerAddresses(uint256 _from, uint256 _count) external view returns(address[] memory) {
        uint256 from = _from;
        uint256 range = _from + _count;
        uint256 index = 0;
        address[] memory mWinners = new address[](range);
        for (from; from < range; ++from) {
            if (from >= winnerAddresses.length) break;
            mWinners[index] = winnerAddresses[from];
            index++;
        }
        return mWinners;
    }

    /**
     * @dev Function to get available deposit tokens
     */
    function getAvailableDepositTokens() external view returns(address[] memory) {
        return availableDepositTokens;
    }

    /**
     * @dev get the sorted bids in chunks
     */
    function getSortedBids(uint256 _from, uint256 _count) external view returns(address[] memory) {
        uint256 from = _from;
        uint256 range = _from + _count;
        uint256 index = 0;
        address[] memory mBids = new address[](range);
        for (from; from < range; ++from) {
            if (from >= sortedBids.length) break;
            mBids[index] = sortedBids[from].bidderAddress;
            index++;
        }
        return mBids;
    }

    /**
     * @dev Function to get all bids
     * @param _bidderAddresses addresses to get bids
     */
    function getBids(address[] memory _bidderAddresses) external view returns(AuctionBid[] memory) {
        AuctionBid[] memory mBidders = new AuctionBid[](_bidderAddresses.length);
        for (uint256 i; i < _bidderAddresses.length; ++i) {
            mBidders[i] = bidders[_bidderAddresses[i]];
        }
        return mBidders;
    }

    /**
     * @dev Function to get winnerbids
     * @param _winnerAddresses addresses to get bids
     */
    function getWinBids(address[] memory _winnerAddresses) external view returns(WinAuctionBid[] memory) {
        WinAuctionBid[] memory mWinners = new WinAuctionBid[](_winnerAddresses.length);
        for (uint256 i; i < _winnerAddresses.length; ++i) {
            mWinners[i] = winners[_winnerAddresses[i]];
        }
        return mWinners;
    }

    /**
     * @dev Function to cancel bid
     */
    function cancel() external onlyStarted {
        require(bidders[msg.sender].depositToken.transfer(msg.sender, bidders[msg.sender].totalPrice), "Token not transferred");
        bidders[msg.sender].canceled = true;

        emit CancelBid(msg.sender);
    }

    /**
     * @dev Function to end auction
     */
    function endAuction() external onlyOwner onlyStarted {
        endAt = uint128(block.timestamp);
        started = false;
        emit EndAuction();
    }

    /**
     * @dev Function to get last winner bid
     */
    function getLastWinnerBid() external view returns(WinAuctionBid memory) {
        uint lastIndex = winnerAddresses.length - 1;
        return winners[winnerAddresses[lastIndex]];
    }

    /**
     * @dev Function to set sorted bids from highest pricePerToken to lowest
     */
    function setSortedBids(address[] memory _bidderAddresses) external onlyOwner onlyEnded {
        require(!bidsSorted, "Should not be sorted");
        require(_bidderAddresses.length > 0, "BidderAddresses should be greater than 0");
        require(bidderAddresses.length > 0, "Bids should be greater than 0");

        for (uint256 i = 0; i < _bidderAddresses.length; ++i) {
            WinAuctionBid memory wonBid = WinAuctionBid({
                tokenAmount: bidders[_bidderAddresses[i]].tokenAmount,
                pricePerToken: bidders[_bidderAddresses[i]].pricePerToken,
                totalPrice: bidders[_bidderAddresses[i]].totalPrice,
                claimed: bidders[_bidderAddresses[i]].claimed,
                bidderAddress: _bidderAddresses[i],
                depositToken: bidders[_bidderAddresses[i]].depositToken
            });
            sortedBids.push(wonBid);

            if ((sortedIndex + i) >= bidderAddresses.length - 1) {
                bidsSorted = true;
                break;
            }
        }
        sortedIndex = sortedIndex + _bidderAddresses.length;
    }

    /**
     * @dev Function to compute the winners ended
     */
    function computeWinners(uint256 _batchSize) external onlyOwner onlyEnded {
        require(!winnersComputed, "Winners should not be computed yet");
        require(bidsSorted, "Should be sorted");
        require(_batchSize >= 1, "BatchSize should be greater than 0");

        uint256 range = computedIndex + _batchSize;
        for (computedIndex; computedIndex < range; ++computedIndex) {
            if (computedIndex > sortedBids.length - 1) {
                winnersComputed = true;
                emit WinnersComputed();
                break;
            }

            WinAuctionBid memory _bid = sortedBids[computedIndex];

            if (_bid.claimed) continue;


            if (totalTokenWon + _bid.tokenAmount > totalTokenAmount && totalTokenWon < totalTokenAmount) {
                _bid.tokenAmount = totalTokenAmount - totalTokenWon;
            } else if (totalTokenWon >= totalTokenAmount) {
                winnersComputed = true;
                emit WinnersComputed();
                break;
            }

            totalTokenWon = totalTokenWon + _bid.tokenAmount;

            uint256 price = _bid.tokenAmount * _bid.pricePerToken;
            uint256 _depositTokenAmount = _bid.depositToken.balanceOf(_bid.bidderAddress);

            if (price > _depositTokenAmount) {
                totalTokenWon = totalTokenWon - _bid.tokenAmount;
                continue;
            }

            winners[_bid.bidderAddress] = _bid;
            winnerAddresses.push(_bid.bidderAddress);
        }
    }

    /**
     * @dev Function to claim token
     */
    function claim() external onlyEnded {
        require(winnersComputed, "Winners should be computed first");
        require(lowestPricesSet, "Lowest prices should be set");

        WinAuctionBid memory wBid = winners[msg.sender];
        if (wBid.tokenAmount > 0) {
            // Transfer nft to user
            rewardToken.safeTransferFrom(
                address(this),
                msg.sender,
                rewardTokenId,
                wBid.tokenAmount,
                "0x"
            );
            // Transfer back balance of deposit token
            uint256 price = wBid.tokenAmount * availableDepositTokenPrices[wBid.depositToken].lowestPrice;

            int256 balance = int256(wBid.totalPrice) - int256(price);
            if (balance > 0) {
                require(wBid.depositToken.transfer(msg.sender, uint256(balance)), "Remaining deposit token was not transferred");
            }

            winners[msg.sender].claimed = true;
        } else {
            // Send back user's deposit token
            AuctionBid memory nBid = bidders[msg.sender];
            require(nBid.tokenAmount > 0, "Not a bidder");
            uint256 depositTokenAmount = nBid.depositToken.balanceOf(msg.sender);
            if (depositTokenAmount > 0) {
                require(nBid.depositToken.transfer(msg.sender, depositTokenAmount), "Token not transferred");
            }
        }

        emit Withdraw(withdrawAddress);
    }
    /**
     * @dev Function to withdraw funds
     */
    function withdraw() external onlyOwner onlyEnded {
        for (uint256 i = 0; i < availableDepositTokens.length; ++i) {
            uint256 _depositTokenAmount = ERC20(availableDepositTokens[i]).balanceOf(address(this));
            require(ERC20(availableDepositTokens[i]).transfer(withdrawAddress, _depositTokenAmount), "Token not transferred");
        }

        uint256 _rewardTokenAmount = rewardToken.balanceOf(address(this), rewardTokenId);


        if (_rewardTokenAmount > 0) {
            rewardToken.safeTransferFrom(address(this), withdrawAddress, rewardTokenId, _rewardTokenAmount, "0x");
        }

        emit Withdraw(withdrawAddress);
    }

    /**
     * @dev get total count of bids
     */
    function getBidCount() external view returns(uint) {
        return bidderAddresses.length;
    }

    /**
     * @dev Function to check if address is contract address
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /**
     * @dev Function to check if a token is available for depositting
     */
    function depositTokenExists(address _tokenAddress) internal view returns (bool) {
        for (uint256 i = 0; i < availableDepositTokens.length; ++i) {
            if (availableDepositTokens[i] == _tokenAddress) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Function to convert a negative int256 to it's absolute
     */
    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}

