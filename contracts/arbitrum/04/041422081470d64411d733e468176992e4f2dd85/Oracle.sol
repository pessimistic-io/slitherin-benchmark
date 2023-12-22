// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./AccessControl.sol";

import "./IOracle.sol";

contract Oracle is AccessControl, IOracle {
    struct Round {
        uint256 timestamp;
        uint256 price;
        address writer;
    }

    bytes32 public constant WRITER_ROLE = keccak256("BALANCE_ORACLE_WRITER");

    /// @dev Prices by timestamp
    mapping(uint256 => Round) public rounds;

    /// @dev round timestamp array
    mapping(uint256 => uint256) public allTimestamps;

    uint256 public roundLength = 0;
    uint8 public decimals;
    Round public latestRoundData;

    /// @dev flag for initializing, default false.
    bool public genesisStarted;

    /// @dev Pair name - BTCUSDT
    string public pairName;

    /// @dev Emit this event when updating writer status
    event WriterUpdated(address indexed writer, bool enabled);
    event AdminUpdated(address indexed admin, bool enabled);
    /// @dev Emit this event when writing a new price round
    event WrotePrice(
        address indexed writer,
        uint256 indexed timestamp,
        uint256 price
    );
    event DecimalChanged(uint8 decimals);

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "NOT_ORACLE_ADMIN");
        _;
    }

    modifier onlyWriter() {
        require(isWriter(msg.sender), "NOT_ORACLE_WRITER");
        _;
    }

    constructor(string memory _pairName, uint8 _decimals) {
        pairName = _pairName;
        decimals = _decimals;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WRITER_ROLE, msg.sender);
    }

    /// @dev Return `true` if the account belongs to the admin role.
    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /// @dev Return `true` if the account belongs to the user role.
    function isWriter(address account) public view returns (bool) {
        return hasRole(WRITER_ROLE, account);
    }

    /// @notice Set new admin of this market
    /// @dev Only owner can set new admin
    /// @param admin_ New admin to set
    function setAdmin(address admin_, bool enable) external onlyAdmin {
        require(admin_ != address(0), "ZERO_ADDRESS");
        emit AdminUpdated(admin_, enable);

        if (enable) {
            require(!hasRole(DEFAULT_ADMIN_ROLE, admin_), "Already enabled.");
            grantRole(DEFAULT_ADMIN_ROLE, admin_);
        } else {
            require(hasRole(DEFAULT_ADMIN_ROLE, admin_), "Already disabled.");
            revokeRole(DEFAULT_ADMIN_ROLE, admin_);
        }
    }

    /// @notice External function to enable/disable price writer
    /// @dev This function is only permitted to the owner
    /// @param writer Writer address to update
    /// @param enable Boolean to enable/disable writer
    function setWriter(address writer, bool enable) external onlyAdmin {
        require(writer != address(0), "ZERO_ADDRESS");
        if (enable) {
            require(!hasRole(WRITER_ROLE, writer), "Already enabled.");
            grantRole(WRITER_ROLE, writer);
        } else {
            require(hasRole(WRITER_ROLE, writer), "Already disabled.");
            revokeRole(WRITER_ROLE, writer);
        }
        emit WriterUpdated(writer, enable);
    }

    /// @dev set decimals
    /// @param _decimals decimals
    function setDecimals(uint8 _decimals) external onlyAdmin {
        decimals = _decimals;

        emit DecimalChanged(decimals);
    }

    /// @notice Internal function that records a new price round
    /// @param timestamp Timestamp should be greater than last round's time, and less then current time.
    /// @param price Price of round
    function _writePrice(uint256 timestamp, uint256 price) internal {
        if (genesisStarted) {
            require(
                timestamp >= latestRoundData.timestamp,
                "INVALID_TIMESTAMP"
            );
        } else {
            genesisStarted = true;
        }

        require(price != 0, "INVALID_PRICE");

        Round storage newRound = rounds[timestamp];
        newRound.price = price;
        newRound.timestamp = timestamp;
        newRound.writer = msg.sender;

        latestRoundData = newRound;

        allTimestamps[roundLength] = timestamp;
        roundLength = roundLength + 1;
        emit WrotePrice(msg.sender, timestamp, price);
    }

    /// @notice External function that records a new price round
    /// @dev This function is only permitted to writers
    /// @param timestamp Timestamp should be greater than last round's time, and less then current time.
    /// @param price Price of round, based 1e18
    function writePrice(uint256 timestamp, uint256 price) external onlyWriter {
        _writePrice(timestamp, price);
    }

    /// @notice External function that records a new price round
    /// @dev This function is only permitted to writers
    /// @param timestamps Array of timestamps
    /// @param prices Array of prices
    function writeBatchPrices(
        uint256[] memory timestamps,
        uint256[] memory prices
    ) external onlyWriter {
        require(timestamps.length == prices.length, "INVALID_ARRAY_LENGTH");
        for (uint256 i = 0; i < timestamps.length; i++) {
            _writePrice(timestamps[i], prices[i]);
        }
        // FIXME you can save gas by not incrementing length ++ but by whole for each length here
    }

    /// @notice External function that returns the price and timestamp by round id
    /// @param timestamp timestamp
    /// @return price Round price
    function getPriceAt(uint256 timestamp)
        external
        view
        returns (uint256 price)
    {
        Round memory round = rounds[timestamp];
        price = round.price;
        require(round.timestamp != 0, "INVALID_TIMESTAMP");
    }

    /// @return writable?
    function isWritable() external pure returns (bool) {
        return true;
    }

    /// @notice Get latest round data
    /// @return timestamp at latest round
    /// @return price at latest round
    function getLatestRoundData()
        external
        view
        returns (uint256 timestamp, uint256 price)
    {
        timestamp = latestRoundData.timestamp;
        price = latestRoundData.price;
    }
}

