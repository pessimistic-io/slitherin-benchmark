// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;
import "./Counters.sol";
import "./IERC20.sol";
import "./draft-IERC20Permit.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./AggregatorV3Interface.sol";
import "./OracleLibrary.sol";
import "./SafeTransfer.sol";
import "./Caller.sol";

contract BidFomo is Caller, ReentrancyGuard {
    using Counters for Counters.Counter;
    struct Pool {
        uint256 period;
        string message;
        uint256 bidding; // usd
        address bidder; // current user
        uint256 bitAt;
        uint256 startTime;
        uint256 endTime;
        uint256 capTime;
    }
    struct HistoryPool {
        uint256 period;
        uint256 bidding;
        address winner;
        uint256 endTime;
        uint256 reward;
        uint256 blockNumber;
    }
    struct UserBid {
        uint256 amount;
        uint256 startAt;
    }

    event Bid(uint256 indexed period, address indexed player, uint256 amount);
    event ConqueringReward(
        uint256 indexed period,
        address indexed player,
        uint256 rewards,
        uint256 startAt,
        uint256 endAt,
        uint256 blockNumber
    );
    event ClaimReward(
        uint256 indexed period,
        address indexed winner,
        uint256 rewards,
        uint256 blockNumber
    );
    event Withdrawal(address indexed user, uint256 amount, uint256 lostAmount);

    address public immutable WETH;
    address public uniswapPool;
    address private chainLinkEth;
    uint256 public capTime = 1 days;
    uint256 public lowerTime = 30 minutes;
    uint256 public rewardRateInPool = 60; //60%
    uint256 public bidGrowthTime = 180; // second
    uint256 public tradeTime = 60; // second
    uint256 public bidPriceGrowthRate = 10; // 1% permillage
    uint256 public rewardPerSecond;
    uint256 public initialPrice = 10 ** 6; // 10**6 usd
    uint256 public capPrice = 50; // permillage of total Supply value
    uint256 public initialTime = 1 hours; // 1 hour

    Counters.Counter private _tokenIds;
    IERC20 public boboToken;
    Pool public pool;
    HistoryPool[] public historyPool;
    mapping(address => UserBid[]) public userBids;
    UserBid[] private tempUserBids;
    bool public paused = false;

    constructor(
        address _weth,
        address _bobo,
        address _devAddress,
        address _chainLinkEth
    ) {
        WETH = _weth;
        boboToken = IERC20(_bobo);
        devAddress = _devAddress;
        chainLinkEth = _chainLinkEth;
        _addCaller(_msgSender());
        _addCaller(devAddress);
        _addCaller(_bobo);
    }

    function start(
        uint256 _initialPrice,
        uint256 _rewardPerSecond,
        address _pool
    ) external onlyManger {
        paused = false;
        initialPrice = _initialPrice;
        rewardPerSecond = _rewardPerSecond;
        uniswapPool = _pool;
        _newPool();
    }

    function setPaused(bool b) external onlyManger {
        paused = b;
    }

    function setSwapPool(address _pool) external onlyManger {
        uniswapPool = _pool;
    }

    function setInitial(
        uint256 _rewardRateInPool,
        uint256 _initialPrice,
        uint256 _initialTime,
        uint256 _bidGrowthTime,
        uint256 _bidPriceGrowthRate,
        uint256 _tradeTime
    ) external onlyManger {
        rewardRateInPool = _rewardRateInPool;
        initialPrice = _initialPrice;
        initialTime = _initialTime;
        bidGrowthTime = _bidGrowthTime;
        bidPriceGrowthRate = _bidPriceGrowthRate;
        tradeTime = _tradeTime;
    }

    function setCapPrice(uint256 _capPrice) external onlyManger {
        capPrice = _capPrice;
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyManger {
        rewardPerSecond = _rewardPerSecond;
    }

    function setBoboToken(IERC20 _boboToken) external onlyManger {
        boboToken = _boboToken;
        _addCaller(address(boboToken));
    }

    function setClipTime(
        uint256 _capTime,
        uint256 _lowerTime
    ) external onlyManger {
        capTime = _capTime;
        lowerTime = _lowerTime;
    }

    function started() external view returns (bool) {
        return pool.period > 0 && !paused;
    }

    function inProgress() public view returns (bool) {
        return pool.period > 0 && block.timestamp < pool.endTime;
    }

    function jackpot() external view returns (uint256 amount) {
        amount = _wethBalance(address(this));
    }

    function conqueringReward() public view returns (uint256) {
        if (pool.period == 0) {
            return 0;
        }
        uint256 endTime = inProgress() ? block.timestamp : pool.endTime;
        uint256 startAt = pool.bitAt == 0 ? pool.startTime : pool.bitAt;
        return (endTime - startAt) * rewardPerSecond;
    }

    function _wethBalance(address addr) internal view returns (uint256 amount) {
        amount = IERC20(WETH).balanceOf(addr);
    }

    function previous() public view returns (HistoryPool memory pre) {
        if (historyPool.length > 0) {
            pre = historyPool[historyPool.length - 1];
        }
    }

    function getHistoryPools() public view returns (HistoryPool[] memory) {
        return historyPool;
    }

    function balance(
        address user,
        bool all
    ) public view returns (uint256 totalAmount, uint256 availableAmount) {
        for (uint256 i = 0; i < userBids[user].length; i++) {
            uint256 elapsed = block.timestamp - userBids[user][i].startAt;
            totalAmount += userBids[user][i].amount;
            if (elapsed >= 3 days) {
                availableAmount += userBids[user][i].amount;
            } else {
                if (all) {
                    availableAmount +=
                        (userBids[user][i].amount * elapsed) /
                        3 days;
                }
            }
        }
    }

    function withdraw(bool all) external {
        (uint256 totalAmount, uint256 availableAmount) = balance(
            _msgSender(),
            all
        );
        require(totalAmount > 0, "Not bid");
        if (!all) {
            require(availableAmount > 0, "Not released amount");
        }
        if (availableAmount > 0) {
            boboToken.transfer(_msgSender(), availableAmount);
        }
        if (all) {
            delete userBids[_msgSender()];
        } else {
            // withdraw released order
            tempUserBids = userBids[_msgSender()];
            delete userBids[_msgSender()];
            for (uint256 i = 0; i < tempUserBids.length; i++) {
                if ((block.timestamp - tempUserBids[i].startAt) < 3 days) {
                    userBids[_msgSender()].push(tempUserBids[i]);
                }
            }
            delete tempUserBids;
        }
        emit Withdrawal(
            _msgSender(),
            availableAmount,
            all ? totalAmount - availableAmount : 0
        );
    }

    function bidSign(
        string memory message,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        IERC20Permit(address(boboToken)).permit(
            owner,
            spender,
            value,
            deadline,
            v,
            r,
            s
        );
        bid(message);
    }

    function bid(string memory message) public {
        require(inProgress(), "This period not start");
        require(
            bytes(message).length > 0 && bytes(message).length <= 30,
            "Message: Max 30 characters"
        );
        (uint256 curBiddingAmount, uint256 bidPrice) = currentBidAmount();
        require(
            boboToken.balanceOf(_msgSender()) >= curBiddingAmount,
            "BOBO: Insufficient balance"
        );
        TransferHelper.safeTransferFrom(
            address(boboToken),
            _msgSender(),
            address(this),
            curBiddingAmount
        );

        claimConqueringReward(pool.bidder);

        pool.bidding = bidPrice;
        pool.bidder = _msgSender();
        pool.message = message;
        pool.bitAt = block.timestamp;

        uint256 remaining = pool.endTime - block.timestamp;
        pool.endTime += (remaining + bidGrowthTime) > pool.capTime
            ? pool.capTime - remaining
            : bidGrowthTime;

        userBids[_msgSender()].push(
            UserBid({amount: curBiddingAmount, startAt: block.timestamp})
        );

        emit Bid(pool.period, _msgSender(), curBiddingAmount);
    }

    function claimConqueringReward(address player) internal {
        if (player != address(0)) {
            uint256 reward = conqueringReward();
            if (reward > 0 && boboToken.balanceOf(address(this)) >= reward) {
                boboToken.transfer(player, reward);
            }
            emit ConqueringReward(
                pool.period,
                player,
                reward,
                pool.bitAt,
                block.timestamp,
                block.number
            );
        }
    }

    // trade event amount must be greater than $100
    function trade(uint8 source, address, uint256 usd) external onlyCaller {
        require(inProgress(), "Not progress");
        require(usd >= 100, "Insufficient USD");
        if (source == 1) {
            // buy
            (pool.capTime + tradeTime) < capTime
                ? (pool.capTime += tradeTime)
                : (pool.capTime = capTime);
        } else {
            // sell
            (pool.capTime - tradeTime) > lowerTime
                ? (pool.capTime -= tradeTime)
                : (pool.capTime = lowerTime);
        }
    }

    function claimReward() external nonReentrant {
        require(!inProgress() && previous().period != pool.period, "not ended");
        uint256 period = pool.period;
        address winner = pool.bidder;
        uint256 reward = winner != address(0)
            ? ((_wethBalance(address(this)) * rewardRateInPool) / 100)
            : 0;
        claimConqueringReward(winner);
        historyPool.push(
            HistoryPool({
                period: pool.period,
                winner: winner,
                bidding: pool.bidding,
                reward: reward,
                endTime: block.timestamp,
                blockNumber: block.number
            })
        );
        if (historyPool.length > 10) {
            delete historyPool[0];
            for (uint i = 0; i < historyPool.length - 1; i++) {
                historyPool[i] = historyPool[i + 1];
            }
        }
        _newPool();
        if (reward > 0 && winner != address(0)) {
            // send eth
            SafeTransfer.unwrapWETH9(WETH, winner, reward);
        }
        emit ClaimReward(period, winner, reward, block.number);
    }

    function _newPool() internal {
        if (paused) {
            return;
        }
        _tokenIds.increment();
        pool.period = _tokenIds.current();
        pool.bidding = initialPrice;
        pool.bidder = address(0);
        pool.bitAt = 0;
        pool.message = "FOMO BOBO";
        pool.capTime = initialTime;
        pool.startTime = block.timestamp;
        pool.endTime = block.timestamp + initialTime;
    }

    // Returns the latest ETH price in USD, need / 1e8
    function ETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(chainLinkEth)
            .latestRoundData();
        return uint256(price);
    }

    // USD, need / 1e(8+18)
    function BOBOPrice() public view returns (uint256 usd, uint256 decimal) {
        decimal = 8 + 18;
        if (uniswapPool == address(0)) {
            return (0, 0);
        }
        (, int24 tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        uint256 amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(10 ** 6),
            address(boboToken),
            WETH
        );
        usd = (ETHPrice() * amountOut);
    }

    function currentBidAmount()
        public
        view
        returns (uint256 amount, uint256 bidPrice)
    {
        bidPrice =
            (pool.bidding *
                (1000 + (pool.bitAt == 0 ? 0 : bidPriceGrowthRate))) /
            1000;
        (uint256 boboPrice, uint256 decimal) = BOBOPrice();
        if (boboPrice == 0) {
            boboPrice = 10 ** decimal / 1000;
        }
        amount = (bidPrice * (10 ** decimal)) / boboPrice;
        uint256 cap = (boboToken.totalSupply() * capPrice) / 1000;
        if (amount > cap) {
            amount = cap;
        }
    }
}

