// SPDX-License-Identifier: MIT

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
        bool claimed; // default false
    }

    /// @dev Market Data
    string public marketName;
    IOracle public oracle;
    IBinaryVault public vault;
    IBinaryConfig public config;

    IERC20 public underlyingToken;

    /// @dev Timeframes supported in this market.
    TimeFrame[] public timeframes;

    /// @dev Rounds per timeframe
    mapping(uint8 => mapping(uint256 => Round)) public rounds; // timeframe id => round id => round

    /// @dev bet info per user and round
    mapping(uint8 => mapping(uint256 => mapping(address => BetInfo)))
        public ledger; // timeframe id => round id => address => bet info

    // @dev user rounds per timeframe
    mapping(uint8 => mapping(address => uint256[])) public userRounds; // timeframe id => user address => round ids

    /// @dev This should be modified
    uint256 public minBetAmount;
    uint256 public oracleLatestTimestamp;
    uint256 public genesisStartBlockTimestamp;
    uint256 public bufferTime = 3 seconds;
    uint256 public bufferForRefund = 30 seconds;

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
        uint256 amount
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

        underlyingToken = IERC20(vault.underlyingTokenAddress());

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
        require(address(config_) != address(0));
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
        // We have 1m, 5m and 15m timeframes. So we will set genesisStartBlockTime base on 15m timeframes.
        genesisStartBlockTimestamp =
            block.timestamp -
            (block.timestamp % _timeframes[2].interval);
        for (uint256 i = 0; i < length; i = i + 1) {
            _startRound(_timeframes[i].id, 0);
        }
        genesisStartOnce = true;
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

        for (uint8 i = 0; i < length; i++) {
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

    /**
     * @dev Current bettable amount.
     * This should be calculated based on vault hourly exposure amount, and current existing bets in all timeframes.
     */
    function getCurrentBettableAmount(uint8 timeframeId, uint256 epoch)
        public
        view
        returns (uint256 bullAmount, uint256 bearAmount)
    {
        uint256 maxMinuteExposure = vault.getMaxHourlyExposure() / 60;
        if (maxMinuteExposure == 0) {
            return (0, 0);
        }

        uint256 currentEpoch = getCurrentRoundId(timeframeId);
        // check if Ahead betting possible
        if (epoch > currentEpoch && !vault.isFutureBettingAvailable()) {
            return (0, 0);
        }

        uint256 endTime = getBlockTimeForEpoch(timeframeId, epoch + 2);

        // Delta amount between bull and bear bets
        (uint256 exposureAmount, uint8 direction) = vault.getExposureAmountAt(
            endTime
        );

        uint256 maxBettableAmount = epoch > currentEpoch
            ? maxMinuteExposure / 2
            : maxMinuteExposure;

        // Current direction is bull
        bullAmount = direction == 0
            ? (
                exposureAmount >= maxBettableAmount
                    ? 0
                    : maxBettableAmount - exposureAmount
            )
            : maxBettableAmount;

        bearAmount = direction == 1
            ? (
                exposureAmount >= maxBettableAmount
                    ? 0
                    : maxBettableAmount - exposureAmount
            )
            : maxBettableAmount;
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

        (uint256 bullAmount, uint256 bearAmount) = getCurrentBettableAmount(
            timeframeId,
            epoch
        );

        if (position == Position.Bull) {
            require(
                bullAmount >= amount,
                "Bet amount exceeds current vault's capacity."
            );
        } else {
            require(
                bearAmount >= amount,
                "Bet amount exceeds current vault's capacity."
            );
        }

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
        // We use block time
        require(
            block.timestamp > rounds[timeframeId][epoch].closeBlockTime,
            "Round has not ended"
        );
        require(!ledger[timeframeId][epoch][user].claimed, "Rewards claimed");

        uint256 rewardAmount = 0;
        bool isRefund;
        BetInfo storage betInfo = ledger[timeframeId][epoch][user];

        // Round valid, claim rewards
        if (rounds[timeframeId][epoch].oracleCalled) {
            require(
                isClaimable(timeframeId, epoch, user),
                "Not eligible for claim"
            );
            rewardAmount = betInfo.amount;
            isRefund = false;
        }
        // Round invalid, refund bet amount
        else {
            require(
                refundable(timeframeId, epoch, user),
                "Not eligible for refund"
            );

            rewardAmount = betInfo.amount;
            isRefund = true;
        }

        betInfo.claimed = true;
        uint256 claimedAmount = vault.claimBettingRewards(
            user,
            rewardAmount,
            isRefund
        );

        emit Claimed(marketName, user, timeframeId, epoch, claimedAmount);
    }

    /**
     * @notice claim winning rewards
     * @param timeframeId Timeframe ID to claim winning rewards
     * @param epoch round id
     */
    function claim(uint8 timeframeId, uint256 epoch) external nonReentrant {
        _claim(msg.sender, timeframeId, epoch);
    }

    /**
     * @notice Batch claim winning rewards
     * @param timeframeIds Timeframe IDs to claim winning rewards
     * @param epochs round ids
     */
    function claimBatch(uint8[] memory timeframeIds, uint256[][] memory epochs)
        external
        nonReentrant
    {
        uint256 tLength = timeframeIds.length;
        require(tLength == epochs.length, "INVALID_ARRAY_LENGTH");

        for (uint256 i = 0; i < tLength; i = i + 1) {
            uint8 timeframeId = timeframeIds[i];
            uint256 eLength = epochs[i].length;

            for (uint256 j = 0; j < eLength; j = j + 1) {
                _claim(msg.sender, timeframeId, epochs[i][j]);
            }
        }
    }

    /**
     * @notice Batch claim emergency from admin
     * @param user user address for claim(refund)
     * @param timeframeIds Timeframe IDs to claim winning rewards
     * @param epochs round ids
     */
    function claimEmergency(
        address user,
        uint8[] memory timeframeIds,
        uint256[][] memory epochs
    ) external onlyAdmin {
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
        return
            round.oracleCalled &&
            betInfo.amount > 0 &&
            !betInfo.claimed &&
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
            !round.oracleCalled &&
            block.timestamp > round.closeBlockTime + bufferForRefund &&
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
        external
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
        for (uint256 i = 0; i < length; i++) {
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
    function setTimeframes(TimeFrame[] memory timeframes_) external onlyAdmin {
        uint256 length = timeframes_.length;
        require(length > 0, "INVALID_ARRAY_LENGTH");

        for (uint256 i = 0; i < length; i = i + 1) {
            timeframes.push(timeframes_[i]);
        }
    }
}

