// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Pausable.sol";
import "./SafeERC20.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";

import "./IBinaryMarket.sol";
import "./IBinaryConfig.sol";

contract BinaryMarket is
    Pausable,
    IBinaryMarket,
    AccessControl,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum Position {
        Bull,
        Bear
    }

    struct TimeFrame {
        uint8 id;
        uint256 interval;
    }

    struct Round {
        uint256 epoch;
        uint256 startBlockTime; // start block time
        uint256 lockBlockTime; // lock block time
        uint256 closeBlockTime; // close block time
        uint256 lockPrice;
        uint256 closePrice;
        uint256 lockOracleTimestamp;
        uint256 closeOracleTimestamp;
        uint256 totalAmount;
        uint256 bullAmount;
        uint256 bearAmount;
        bool oracleCalled;
    }

    struct BetInfo {
        Position position;
        uint256 amount;
        bool isReverted; // default false
        bool claimed; // default false
    }

    uint256 private constant MAX_BET_INTERVAL = 3600; // 1 hour

    /// @dev Market Data
    string public marketName;
    IOracle public oracle;
    IBinaryVault public immutable vault;
    IBinaryConfig public config;

    /// @dev Timeframes supported in this market.
    TimeFrame[] public timeframes;

    mapping(uint256 => uint256) public exposureBipsForTimeframe;

    /// @dev Rounds per timeframe
    mapping(uint8 => mapping(uint256 => Round)) public rounds; // timeframe id => round id => round

    /// @dev bet info per user and round
    mapping(uint8 => mapping(uint256 => mapping(address => BetInfo)))
        public ledger; // timeframe id => round id => address => bet info

    // @dev user rounds per timeframe
    mapping(uint8 => mapping(address => uint256[])) public userRounds; // timeframe id => user address => round ids

    // @dev users who placed bet
    mapping(uint8 => mapping(uint256 => address[])) public users; // timeframe id => round id => user addresses

    mapping(uint8 => bool) public disabledTimeframes; // timeframe id => bool
    mapping(uint8 => uint256) public explicitMaxBetAmounts; // timeframe id => max bet amount

    /// @dev This should be modified
    uint256 public minBetAmount;
    uint256 public oracleLatestTimestamp;
    uint256 public genesisStartBlockTimestamp;
    uint256 public bufferTime = 3 seconds;
    uint256 public bufferForRefund = 30 seconds;
    uint256 private totalBetsInInterval;

    /// @dev default false
    bool public genesisStartOnce;
    /// @dev timeframe id => genesis locked? default false
    mapping(uint8 => bool) public genesisLockedOnce;

    event PositionOpened(
        string indexed marketName,
        address user,
        uint256 amount,
        uint8 timeframeId,
        uint256 roundId,
        Position position
    );

    event Claimed(
        string indexed marketName,
        address indexed user,
        uint8 timeframeId,
        uint256 indexed roundId,
        uint256 amount,
        bool isRefund
    );

    event StartRound(
        uint8 indexed timeframeId,
        uint256 indexed epoch,
        uint256 startTime
    );
    event LockRound(
        uint8 indexed timeframeId,
        uint256 indexed epoch,
        uint256 indexed oracleTimestamp,
        uint256 price
    );
    event EndRound(
        uint8 indexed timeframeId,
        uint256 indexed epoch,
        uint256 indexed oracleTimestamp,
        uint256 price
    );

    event BetReverted(
        uint8 indexed timeframeId,
        uint256 indexed epoch,
        address[] users
    );

    event GenesisStartTimeSet(
        uint256 oldTime,
        uint256 newTime
    );

    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    event MarketNameChanged(string oldName, string newName);
    event AdminChanged(address indexed admin, bool enabled);
    event OperatorChanged(address indexed operator, bool enabled);
    event MinBetAmountChanged(uint256 newAmount, uint256 oldAmount);

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "ONLY_ADMIN");
        _;
    }

    modifier onlyOperator() {
        require(isOperator(msg.sender), "ONLY_OPERATOR");
        _;
    }

    constructor(
        IBinaryConfig config_,
        IOracle oracle_,
        IBinaryVault vault_,
        string memory marketName_,
        uint256 minBetAmount_
    ) {
        require(address(oracle_) != address(0), "ZERO_ADDRESS");
        require(address(vault_) != address(0), "ZERO_ADDRESS");
        require(address(config_) != address(0), "ZERO_ADDRESS");

        oracle = oracle_;
        vault = vault_;
        config = config_;

        marketName = marketName_;
        minBetAmount = minBetAmount_;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @notice Set oracle of underlying token of this market
     * @dev Only owner can set the oracle
     * @param oracle_ New oracle address to set
     */
    function setOracle(IOracle oracle_) external onlyAdmin {
        require(address(oracle_) != address(0), "ZERO_ADDRESS");
        emit OracleChanged(address(oracle), address(oracle_));
        oracle = oracle_;
        oracleLatestTimestamp = 0;
    }

    /**
     * @notice Set name of this market
     * @dev Only owner can set name
     * @param name_ New name to set
     */
    function setName(string memory name_) external onlyAdmin {
        emit MarketNameChanged(marketName, name_);
        marketName = name_;
    }

    /**
     * @notice Set new admin of this market
     * @dev Only owner can set new admin
     * @param admin_ New admin to set
     */
    function setAdmin(address admin_, bool enable) external onlyAdmin {
        require(admin_ != address(0), "ZERO_ADDRESS");
        emit AdminChanged(admin_, enable);

        if (enable) {
            require(hasRole(DEFAULT_ADMIN_ROLE, admin_), "Already enabled.");
            grantRole(DEFAULT_ADMIN_ROLE, admin_);
        } else {
            require(!hasRole(DEFAULT_ADMIN_ROLE, admin_), "Already disabled.");
            revokeRole(DEFAULT_ADMIN_ROLE, admin_);
        }
    }

    /**
     * @notice Set new operator of this market
     * @dev Only admin can set new operator
     * @param operator_ New operator to set
     */
    function setOperator(address operator_, bool enable) external onlyAdmin {
        require(operator_ != address(0), "ZERO_ADDRESS");
        emit OperatorChanged(operator_, enable);

        if (enable) {
            require(!hasRole(OPERATOR_ROLE, operator_), "Already enabled.");
            grantRole(OPERATOR_ROLE, operator_);
        } else {
            require(hasRole(OPERATOR_ROLE, operator_), "Already disabled.");
            revokeRole(OPERATOR_ROLE, operator_);
        }
    }

    /**
     * @notice Set config
     */
    function setConfig(IBinaryConfig config_) external onlyAdmin {
        require(address(config_) != address(0), "INVALID_ADDRESS");
        config = config_;
    }

    /**
     * @dev Get latest recorded price from oracle
     */
    function _getPriceFromOracle() internal returns (uint256, uint256) {
        (uint256 timestamp, uint256 price) = oracle.getLatestRoundData();
        require(timestamp >= oracleLatestTimestamp, "INVALID_ORACLE_TIMESTAMP");
        oracleLatestTimestamp = timestamp;
        return (timestamp, price);
    }

    function _writeOraclePrice(uint256 timestamp, uint256 price) internal {
        if (oracle.isWritable()) {
            uint256 _timestamp = timestamp - (timestamp % 60); // Standardize
            oracle.writePrice(_timestamp, price);
        }
    }

    /**
     * @dev Start genesis round
     */
    function genesisStartRound() external onlyOperator whenNotPaused {
        require(!genesisStartOnce, "Can only run genesisStartRound once");

        // Gas efficient
        TimeFrame[] memory _timeframes = timeframes;
        uint256 length = _timeframes.length;
        // We have various timeframes. So we will set genesisStartBlockTime base on MAX_BET_INTERVAL.
        genesisStartBlockTimestamp =
            block.timestamp -
            (block.timestamp % MAX_BET_INTERVAL);
        for (uint256 i = 0; i < length; i = i + 1) {
            uint256 epoch = getRoundIdAt(_timeframes[i].id, block.timestamp);
            _startRound(_timeframes[i].id, epoch);
        }
        genesisStartOnce = true;

        emit GenesisStartTimeSet(0, genesisStartBlockTimestamp);
    }

    /**
     * @dev Lock genesis round
     */
    function genesisLockRound(uint8 timeframeId)
        external
        onlyOperator
        whenNotPaused
    {
        require(
            genesisStartOnce,
            "Can only run after genesisStartRound is triggered"
        );
        require(
            !genesisLockedOnce[timeframeId],
            "Can only run genesisLockRound once"
        );

        _writeOraclePrice(block.timestamp, 1 wei);
        (
            uint256 currentTimestamp,
            uint256 currentPrice
        ) = _getPriceFromOracle();
        uint256 currentEpoch = getCurrentRoundId(timeframeId);

        _safeLockRound(
            timeframeId,
            currentEpoch - 1,
            currentTimestamp,
            currentPrice
        );
        _startRound(timeframeId, currentEpoch);
        genesisLockedOnce[timeframeId] = true;
    }

    function _executeRound(
        uint8[] memory timeframeIds,
        uint256[] memory roundIds,
        uint256 price
    ) internal {
        require(
            genesisStartOnce,
            "Can only run after genesisStartRound is triggered"
        );
        uint256 length = timeframeIds.length;

        require(length <= timeframes.length, "Invalid timeframe ids length");
        // Update oracle price
        _writeOraclePrice(block.timestamp, price);

        (
            uint256 currentTimestamp,
            uint256 currentPrice
        ) = _getPriceFromOracle();

        for (uint8 i = 0; i < length; i = i + 1) {
            uint8 timeframeId = timeframeIds[i];
            if (genesisLockedOnce[timeframeId]) {
                uint256 currentEpoch = roundIds[i];
                // Check user list and mark bets refundable
                _checkBetPool(timeframeId, currentEpoch - 1);

                // CurrentEpoch refers to previous round (n-1)
                _safeLockRound(
                    timeframeId,
                    currentEpoch - 1,
                    currentTimestamp,
                    currentPrice
                );
                _safeEndRound(
                    timeframeId,
                    currentEpoch - 2,
                    currentTimestamp,
                    currentPrice
                );

                // Increment currentEpoch to current round (n)
                _safeStartRound(timeframeId, currentEpoch);
            }
        }
        // update max bet amount and max exposure amount
        vault.updateExposureAmount();
    }

    /**
     * @dev Execute round
     */
    function executeRound(
        uint8[] memory timeframeIds,
        uint256[] memory roundIds,
        uint256 price
    ) external onlyOperator whenNotPaused {
        _executeRound(timeframeIds, roundIds, price);
    }

    /**
     * @dev Start the next round n, lock price for round n-1, end round n-2
     */
    function executeCurrentRound(uint8[] memory timeframeIds, uint256 price)
        external
        onlyOperator
        whenNotPaused
    {
        uint256 length = timeframeIds.length;
        uint256[] memory roundIds = new uint256[](length);

        for (uint8 i = 0; i < length; ++i) {
            roundIds[i] = getCurrentRoundId(timeframeIds[i]);
        }

        _executeRound(timeframeIds, roundIds, price);
    }

    /**
     * @dev Start round
     * Previous locked round must end
     */
    function _safeStartRound(uint8 timeframeId, uint256 epoch) internal {
        // We use block time for all compare action.
        if (rounds[timeframeId][epoch - 2].closeBlockTime > 0) {
            require(
                block.timestamp >=
                    rounds[timeframeId][epoch - 2].closeBlockTime - bufferTime,
                "Can only start new round after locked round's closeBlock"
            );
        }

        if (rounds[timeframeId][epoch].startBlockTime == 0) {
            _startRound(timeframeId, epoch);
        }
    }

    function _startRound(uint8 timeframeId, uint256 epoch) internal {
        Round storage round = rounds[timeframeId][epoch];
        // We use block time instead of block number

        uint256 startTime = getBlockTimeForEpoch(timeframeId, epoch);

        round.startBlockTime = startTime;
        round.lockBlockTime = startTime + timeframes[timeframeId].interval;
        round.closeBlockTime = startTime + timeframes[timeframeId].interval * 2;

        round.epoch = epoch;

        emit StartRound(timeframeId, epoch, round.startBlockTime);
    }

    /**
     * @dev Lock round
     */
    function _safeLockRound(
        uint8 timeframeId,
        uint256 epoch,
        uint256 timestamp,
        uint256 price
    ) internal {
        uint256 lockBlockTime = rounds[timeframeId][epoch].lockBlockTime;

        if (
            lockBlockTime > 0 &&
            timestamp >= lockBlockTime - bufferTime &&
            timestamp <= lockBlockTime + 60
        ) {
            require(
                rounds[timeframeId][epoch].lockOracleTimestamp == 0,
                "Already locked."
            );
            _lockRound(timeframeId, epoch, timestamp, price);
        }
    }

    function _lockRound(
        uint8 timeframeId,
        uint256 epoch,
        uint256 timestamp,
        uint256 price
    ) internal {
        Round storage round = rounds[timeframeId][epoch];
        round.lockPrice = price;
        round.lockOracleTimestamp = timestamp;

        emit LockRound(timeframeId, epoch, timestamp, round.lockPrice);
    }

    /**
     * @dev End round
     */
    function _safeEndRound(
        uint8 timeframeId,
        uint256 epoch,
        uint256 timestamp,
        uint256 price
    ) internal {
        uint256 closeBlockTime = rounds[timeframeId][epoch].closeBlockTime;
        /// @dev We allow to write price between [closeBlockTime, close block time + 1m] only.
        if (
            closeBlockTime > 0 &&
            timestamp >= closeBlockTime - bufferTime &&
            timestamp <= closeBlockTime + 60 &&
            rounds[timeframeId][epoch].lockOracleTimestamp > 0
        ) {
            // Already started and locked round
            require(!rounds[timeframeId][epoch].oracleCalled, "Already ended.");
            _endRound(timeframeId, epoch, timestamp, price);
        }
    }

    function _endRound(
        uint8 timeframeId,
        uint256 epoch,
        uint256 timestamp,
        uint256 price
    ) internal {
        Round storage round = rounds[timeframeId][epoch];
        round.closePrice = price;
        round.closeOracleTimestamp = timestamp;
        round.oracleCalled = true;

        // Update vault deposited amount based on bet results
        bool isBull = round.closePrice > round.lockPrice;
        bool isBear = round.closePrice < round.lockPrice;

        uint256 willClaimAmount = 0;
        uint256 willDepositAmount = 0;

        if (isBull) {
            willClaimAmount = round.bullAmount;
            willDepositAmount = round.bearAmount;
        }
        if (isBear) {
            willClaimAmount = round.bearAmount;
            willDepositAmount = round.bullAmount;
        }

        if (!isBull && !isBear) {
            willDepositAmount = round.bullAmount + round.bearAmount;
        }

        vault.onRoundExecuted(willClaimAmount, willDepositAmount);

        emit EndRound(timeframeId, epoch, timestamp, round.closePrice);
    }

    /// @dev currentMaxExposure, currentBet, futureBet amounts
    function _getBettableAmounts(uint8 timeframeId)
        private
        view
        returns (
            uint256 currentExposureAmount,
            uint256 betAmount,
            uint256 futureAmount
        )
    {
        bool isDisabled = disabledTimeframes[timeframeId];
        if (isDisabled) {
            return (0, 0, 0);
        }

        uint256 explicitAmount = explicitMaxBetAmounts[timeframeId];

        if (explicitAmount > 0) {
            uint256 exposure = explicitAmount;
            uint256 maxBet = explicitAmount * config.bettingAmountBips() / config.FEE_BASE();
            return (exposure, maxBet , maxBet / 2);
        }

        uint256 maxHourlyExposure = vault.getCurrentHourlyExposureAmount();

        uint256 totalBetsForInterval = totalBetsInInterval;

        uint256 multiplier = config.multiplier();

        if (maxHourlyExposure > 0) {
            // We need to pull exposure % of current market from vault.
            (, uint256 exposureBips) = vault.whitelistMarkets(address(this));
            maxHourlyExposure =
                (maxHourlyExposure * exposureBips) /
                config.FEE_BASE();

            currentExposureAmount =
                (maxHourlyExposure * multiplier) /
                100 /
                totalBetsForInterval;

            betAmount =
                (currentExposureAmount * config.bettingAmountBips()) /
                config.FEE_BASE();

            // check if Ahead betting possible
            if (!vault.isFutureBettingAvailable()) {
                futureAmount = 0;
            } else {
                // calculate future bet amount
                futureAmount = betAmount / 2;
            }
        }

        return (currentExposureAmount, betAmount, futureAmount);
    }

    function _checkBetPool(uint8 timeframeId, uint256 epoch) private {
        Round storage round = rounds[timeframeId][epoch];
        uint256 exposureAmount;
        Position direction;
        if (round.bullAmount > round.bearAmount) {
            exposureAmount = round.bullAmount - round.bearAmount;
            direction = Position.Bull;
        } else {
            exposureAmount = round.bearAmount - round.bullAmount;
            direction = Position.Bear;
        }

        (uint256 currentMaxExposureAmount, , ) = _getBettableAmounts(timeframeId);

        if (currentMaxExposureAmount < exposureAmount) {
            uint256 deltaExposure = exposureAmount - currentMaxExposureAmount;
            // In this case, we should revert some of last bets
            address[] memory userList = users[timeframeId][epoch];
            address[] memory revertedUsers = new address[](userList.length);

            uint256 accumulatedBets;
            uint256 revertedCount;
            for (uint256 i = userList.length - 1; i > 0; i--) {
                address user = userList[i];
                BetInfo storage betInfo = ledger[timeframeId][epoch][user];
                if (deltaExposure <= accumulatedBets) {
                    break;
                }

                if (betInfo.position == direction) {
                    betInfo.isReverted = true;
                    accumulatedBets += betInfo.amount;

                    revertedUsers[revertedCount] = user;
                    revertedCount++;
                }
            }

            if (direction == Position.Bull) {
                round.bullAmount -= accumulatedBets;
            } else {
                round.bearAmount -= accumulatedBets;
            }

            if (revertedCount > 0) {
                round.totalAmount -= accumulatedBets;
                uint256 toDrop = userList.length - revertedCount;
                if (toDrop > 0) {
                    // solhint-disable-next-line
                    assembly {
                        mstore(revertedUsers, sub(mload(revertedUsers), toDrop))
                    }
                }
                emit BetReverted(timeframeId, epoch, revertedUsers);
            }
        }
    }

    /**
     * @dev Bet bear position
     * @param amount Bet amount
     * @param timeframeId id of 1m/5m/10m
     * @param position bull/bear
     */
    function openPosition(
        uint256 amount,
        uint8 timeframeId,
        uint256 epoch,
        Position position
    ) external whenNotPaused {
        require(
            genesisStartOnce && genesisLockedOnce[timeframeId],
            "Can only place bet after genesisStartOnce and genesisLockedOnce"
        );

        require(
            amount >= minBetAmount,
            "Bet amount must be greater than minBetAmount"
        );
        require(
            ledger[timeframeId][epoch][msg.sender].amount == 0,
            "Can only bet once per round"
        );

        vault.updateExposureAmount();

        uint256 maxBetAmount = getCurrentBettableAmount(timeframeId, epoch);

        require(
            maxBetAmount >= amount,
            "Bet amount exceeds current max amount."
        );

        if (rounds[timeframeId][epoch].startBlockTime == 0) {
            _startRound(timeframeId, epoch);
        }
        require(_bettable(timeframeId, epoch), "Round not bettable");

        uint256 endTime = getBlockTimeForEpoch(timeframeId, epoch + 2);

        // Transfer token to vault
        vault.onPlaceBet(amount, msg.sender, endTime, uint8(position));

        // Update round data
        Round storage round = rounds[timeframeId][epoch];
        round.totalAmount = round.totalAmount + amount;

        if (position == Position.Bear) {
            round.bearAmount = round.bearAmount + amount;
        } else {
            round.bullAmount = round.bullAmount + amount;
        }

        // Update user data
        BetInfo storage betInfo = ledger[timeframeId][epoch][msg.sender];
        betInfo.position = position;
        betInfo.amount = amount;
        userRounds[timeframeId][msg.sender].push(epoch);
        users[timeframeId][epoch].push(msg.sender);

        emit PositionOpened(
            marketName,
            msg.sender,
            amount,
            timeframeId,
            epoch,
            position
        );
    }

    function _claim(
        address user,
        uint8 timeframeId,
        uint256 epoch
    ) internal {
        require(!ledger[timeframeId][epoch][user].claimed, "Rewards claimed");

        uint256 rewardAmount = 0;
        bool isRefund;
        BetInfo storage betInfo = ledger[timeframeId][epoch][user];

        if (isClaimable(timeframeId, epoch, user)) {
            rewardAmount = betInfo.amount;
        } else if (refundable(timeframeId, epoch, user)) {
            isRefund = true;
            rewardAmount = betInfo.amount;
        } else {
            revert("Not eligible for claim or refund");
        }

        betInfo.claimed = true;
        uint256 claimedAmount = vault.claimBettingRewards(
            user,
            rewardAmount,
            isRefund
        );

        emit Claimed(
            marketName,
            user,
            timeframeId,
            epoch,
            claimedAmount,
            isRefund
        );
    }

    /**
     * @notice claim winning rewards
     * @param timeframeId Timeframe ID to claim winning rewards
     * @param epoch round id
     */
    function claim(
        address user,
        uint8 timeframeId,
        uint256 epoch
    ) external nonReentrant {
        _claim(user, timeframeId, epoch);
    }

    /**
     * @notice Batch claim winning rewards
     * @param timeframeIds Timeframe IDs to claim winning rewards
     * @param epochs round ids
     */
    function claimBatch(
        address user,
        uint8[] memory timeframeIds,
        uint256[][] memory epochs
    ) external nonReentrant {
        uint256 tLength = timeframeIds.length;
        require(tLength == epochs.length, "INVALID_ARRAY_LENGTH");

        for (uint256 i = 0; i < tLength; i = i + 1) {
            uint8 timeframeId = timeframeIds[i];
            uint256 eLength = epochs[i].length;

            for (uint256 j = 0; j < eLength; j = j + 1) {
                _claim(user, timeframeId, epochs[i][j]);
            }
        }
    }

    /**
     * @dev Get the claimable stats of specific epoch and user account
     */
    function isClaimable(
        uint8 timeframeId,
        uint256 epoch,
        address user
    ) public view returns (bool) {
        BetInfo memory betInfo = ledger[timeframeId][epoch][user];
        Round memory round = rounds[timeframeId][epoch];
        if (round.lockPrice == round.closePrice) {
            return false;
        }

        if (block.timestamp < round.closeBlockTime) {
            return false;
        }

        return
            round.oracleCalled &&
            betInfo.amount > 0 &&
            !betInfo.claimed &&
            !betInfo.isReverted &&
            ((round.closePrice > round.lockPrice &&
                betInfo.position == Position.Bull) ||
                (round.closePrice < round.lockPrice &&
                    betInfo.position == Position.Bear));
    }

    /**
     * @dev Determine if a round is valid for receiving bets
     * Round must have started and locked
     * Current block must be within startBlock and closeBlock
     */
    function _bettable(uint8 timeframeId, uint256 epoch)
        internal
        view
        returns (bool)
    {
        // start time for epoch
        uint256 timestamp = getBlockTimeForEpoch(timeframeId, epoch);

        // not bettable if current block time is after lock time
        if (
            block.timestamp >=
            timestamp + timeframes[timeframeId].interval - bufferTime
        ) {
            return false;
        }

        if (timestamp > block.timestamp + config.futureBettingTimeUpTo()) {
            return false;
        }

        return rounds[timeframeId][epoch].lockOracleTimestamp == 0;
    }

    /**
     * @dev Get the refundable stats of specific epoch and user account
     */
    function refundable(
        uint8 timeframeId,
        uint256 epoch,
        address user
    ) public view returns (bool) {
        BetInfo memory betInfo = ledger[timeframeId][epoch][user];
        Round memory round = rounds[timeframeId][epoch];
        return
            (betInfo.isReverted ||
                (!round.oracleCalled &&
                    block.timestamp >
                    round.closeBlockTime + bufferForRefund)) &&
            !betInfo.claimed &&
            betInfo.amount > 0;
    }

    /**
     * @dev Pause/unpause
     */

    function setPause(bool value) external onlyOperator {
        if (value) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @dev set minBetAmount
     * callable by admin
     */
    function setMinBetAmount(uint256 _minBetAmount) external onlyAdmin {
        emit MinBetAmountChanged(_minBetAmount, minBetAmount);
        minBetAmount = _minBetAmount;
    }

    function isNecessaryToExecute(uint8 timeframeId)
        public
        view
        returns (bool)
    {
        if (!genesisLockedOnce[timeframeId] || !genesisStartOnce) {
            return false;
        }

        uint256 currentEpoch = getCurrentRoundId(timeframeId);

        if (currentEpoch < 2) return false;

        Round memory round = rounds[timeframeId][currentEpoch];
        Round memory currentRound = rounds[timeframeId][currentEpoch - 1];
        Round memory prevRound = rounds[timeframeId][currentEpoch - 2];

        uint256 lockBlockTimeOfCurrentRound = getBlockTimeForEpoch(
            timeframeId,
            currentEpoch - 1
        ) + timeframes[timeframeId].interval;

        // We use block time
        bool lockable = currentRound.lockOracleTimestamp == 0 &&
            block.timestamp >= lockBlockTimeOfCurrentRound &&
            block.timestamp <= lockBlockTimeOfCurrentRound + 60;

        bool closable = !prevRound.oracleCalled &&
            block.timestamp >= lockBlockTimeOfCurrentRound;

        return
            lockable &&
            closable &&
            (currentRound.totalAmount > 0 ||
                prevRound.totalAmount > 0 ||
                round.totalAmount > 0);
    }

    /**
        @dev check if bet is active
     */

    function getExecutableTimeframes()
        public
        view
        returns (uint8[] memory result)
    {
        // gas optimized
        TimeFrame[] memory _timeframes = timeframes;
        uint256 length = _timeframes.length;

        result = new uint8[](length);
        uint256 count;

        for (uint256 i = 0; i < length; i = i + 1) {
            uint8 timeframeId = _timeframes[i].id;

            if (isNecessaryToExecute(timeframeId)) {
                result[count] = timeframeId;
                count = count + 1;
            }
        }

        uint256 toDrop = length - count;
        if (toDrop > 0) {
            // solhint-disable-next-line
            assembly {
                mstore(result, sub(mload(result), toDrop))
            }
        }
    }

    /**
     * @dev Return round epochs that a user has participated in specific timeframe
     */
    function getUserRounds(
        uint8 timeframeId,
        address user,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > userRounds[timeframeId][user].length - cursor) {
            length = userRounds[timeframeId][user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            values[i] = userRounds[timeframeId][user][cursor + i];
        }

        return (values, cursor + length);
    }

    /**
     * @dev Calculate current round based on genesis timestamp and block number
     * @param timeframeId timeframe id what we want to get round number
     */
    function getCurrentRoundId(uint8 timeframeId)
        public
        view
        returns (uint256 roundFromBlockTime)
    {
        return getRoundIdAt(timeframeId, block.timestamp);
    }

    /**
     * @dev Calculate round id for specific timestamp and block
     */
    function getRoundIdAt(uint8 timeframeId, uint256 timestamp)
        public
        view
        returns (uint256 roundFromBlockTime)
    {
        roundFromBlockTime =
            (timestamp - genesisStartBlockTimestamp) /
            timeframes[timeframeId].interval;
    }

    /**
     * @dev Get block from epoch
     */
    function getBlockTimeForEpoch(uint8 timeframeId, uint256 epoch)
        public
        view
        returns (uint256 timestamp)
    {
        timestamp =
            genesisStartBlockTimestamp +
            epoch *
            timeframes[timeframeId].interval;
    }

    /**
     * @dev Check if round is bettable
     */
    function isBettable(uint8 timeframeId, uint256 epoch)
        external
        view
        returns (bool)
    {
        return _bettable(timeframeId, epoch);
    }

    /// @dev Return `true` if the account belongs to the admin role.
    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /// @dev Return `true` if the account belongs to the user role.
    function isOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /// @dev Set buffer time
    function setBufferTime(uint256 _bufferTime, uint256 _bufferForRefund)
        external
        onlyOperator
    {
        bufferTime = _bufferTime;
        bufferForRefund = _bufferForRefund;
    }

    /// @dev set timeframes
    function addTimeframes(TimeFrame[] memory timeframes_, bool isNew) external onlyAdmin {
        uint256 length = timeframes_.length;
        require(length > 0, "INVALID_ARRAY_LENGTH");
        
        if (isNew) {
            delete timeframes;
            totalBetsInInterval = 0;
        }

        uint256 _totalBets;
        for (uint256 i = 0; i < length; i = i + 1) {
            timeframes.push(timeframes_[i]);
            _totalBets += 1 hours / timeframes_[i].interval;
        }

        totalBetsInInterval += _totalBets;
    }

    function getCurrentBettableAmount(uint8 timeframeId, uint256 epoch)
        public
        view
        returns (uint256)
    {
        uint256 currentEpoch = getCurrentRoundId(timeframeId);
        (, uint256 betAmount, uint256 futureBet) = _getBettableAmounts(timeframeId);
        if (epoch > currentEpoch) {
            return futureBet;
        } else {
            return betAmount;
        }
    }

    
    function disableTimeframe(uint8 timeframeId, bool value) external onlyAdmin {
        require(disabledTimeframes[timeframeId] != value, "Already set");
        disabledTimeframes[timeframeId] = value;

        for (uint256 i = 0; i < timeframes.length; i ++) {
            if (timeframes[i].id == timeframeId) {
                if (!value) {
                    totalBetsInInterval += 1 hours / timeframes[i].interval;
                } else {
                    totalBetsInInterval -= 1 hours / timeframes[i].interval;
                }
                break;
            }
        }
    }

    function setExplicitMaxBetAmount(uint8 timeframeId, uint256 value) external onlyAdmin {
        explicitMaxBetAmounts[timeframeId] = value;
    }

    function setGenesisStartTime(uint256 timestamp) external onlyAdmin {
        emit GenesisStartTimeSet(genesisStartBlockTimestamp, timestamp);
        genesisStartBlockTimestamp = timestamp;
    }
}

