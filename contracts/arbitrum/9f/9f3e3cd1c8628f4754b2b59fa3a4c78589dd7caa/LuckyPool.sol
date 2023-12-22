// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;
import "./Counters.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./SafeTransfer.sol";
import "./Caller.sol";

contract LuckyPool is Caller, ReentrancyGuard {
    using Counters for Counters.Counter;
    struct Pool {
        uint256 period;
        uint256 startTime;
        uint256 endTime;
        uint256 totalWeight;
    }
    struct HistoryPool {
        uint256 period;
        address winner;
        uint256 reward;
        uint256 openTime;
        uint256 blockNumber;
    }
    struct Ticket {
        address user;
        uint256 weight;
        uint256 blockNumber;
    }
    event ClaimReward(
        uint256 indexed period,
        address indexed winner,
        uint256 rewards
    );
    event TicketEvent(
        uint256 indexed period,
        address indexed player,
        uint256 amount
    );

    uint256 public capTime = 30 minutes;
    bool public paused = false;
    address public immutable WETH;
    Counters.Counter private _tokenIds;
    IERC20 public boboToken;
    Pool public pool;
    Ticket[] public tickets;
    HistoryPool[] public historyPool;
    uint256 public cumulativeWinners;
    uint256 public cumulativePlayers;
    uint256 public cumulativeJockpot;

    constructor(address _weth, address _bobo, address _devAddress) {
        WETH = _weth;
        boboToken = IERC20(_bobo);
        devAddress = _devAddress;
        _addCaller(_bobo);
        _addCaller(devAddress);
        _addCaller(_msgSender());
    }

    function start() external onlyManger {
        paused = false;
        delete tickets;
        _newPool();
    }

    function setPaused(bool b) external onlyManger {
        paused = b;
    }

    function setBoboToken(IERC20 _boboToken) external onlyManger {
        boboToken = _boboToken;
        _addCaller(address(boboToken));
    }

    function setCapTime(uint256 _capTime) external onlyManger {
        capTime = _capTime;
    }

    function inProgress() public view returns (bool) {
        return pool.period > 0 && block.timestamp < pool.endTime;
    }

    function jackpot() external view returns (uint256 amount) {
        amount = _wethBalance(address(this));
    }

    function _wethBalance(address addr) internal view returns (uint256 amount) {
        amount = IERC20(WETH).balanceOf(addr);
    }

    function _getRandomNumber(uint256 max) internal view returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(block.timestamp, block.difficulty))
            ) % max;
    }

    function previous() public view returns (HistoryPool memory pre) {
        if (historyPool.length > 0) {
            pre = historyPool[historyPool.length - 1];
        }
    }

    function getLatestTickets(
        uint256 length
    ) public view returns (Ticket[] memory _tickets) {
        uint256 len = length > tickets.length ? tickets.length : length;
        _tickets = new Ticket[](len);
        for (uint256 i = 0; i < len; i++) {
            _tickets[i] = tickets[i];
        }
        return _tickets;
    }

    function getHistoryPools() public view returns (HistoryPool[] memory) {
        return historyPool;
    }

    // buy trade amount must be greater than $100
    function trade(
        uint8 source,
        address user,
        uint256 usd
    ) external onlyCaller {
        require(inProgress(), "not progress");
        require(usd >= 100, "Insufficient USD");
        require(source == 1, "Not buy");
        tickets.push(
            Ticket({user: user, weight: usd, blockNumber: block.number})
        );
        pool.totalWeight += usd;
        cumulativePlayers++;
        emit TicketEvent(pool.period, user, usd);
    }

    function claimReward() external nonReentrant {
        require(!inProgress() && previous().period != pool.period, "not ended");
        uint256 reward = 0;
        address winner;
        if (pool.totalWeight > 0) {
            uint256 randomNumber = _getRandomNumber(pool.totalWeight);
            uint256 cumulativeWeight = 0;
            for (uint256 i = 0; i < tickets.length; i++) {
                cumulativeWeight += tickets[i].weight;
                if (randomNumber < cumulativeWeight) {
                    winner = tickets[i].user;
                    break;
                }
            }
            reward = _wethBalance(address(this));
            cumulativeJockpot += reward;
            cumulativeWinners++;
        }
        emit ClaimReward(pool.period, winner, reward);
        historyPool.push(
            HistoryPool({
                period: pool.period,
                winner: winner,
                reward: reward,
                openTime: block.timestamp,
                blockNumber: block.number
            })
        );
        if (historyPool.length > 10) {
            delete historyPool[0];
            for (uint i = 0; i < historyPool.length - 1; i++) {
                historyPool[i] = historyPool[i + 1];
            }
        }
        delete tickets;
        _newPool();
        if (reward > 0 && winner != address(0)) {
            // send eth
            SafeTransfer.unwrapWETH9(WETH, winner, reward);
        }
    }

    function _newPool() internal {
        if (paused) {
            return;
        }
        _tokenIds.increment();
        pool.period = _tokenIds.current();
        pool.startTime = block.timestamp;
        pool.endTime = block.timestamp + capTime;
        pool.totalWeight = 0;
    }
}

