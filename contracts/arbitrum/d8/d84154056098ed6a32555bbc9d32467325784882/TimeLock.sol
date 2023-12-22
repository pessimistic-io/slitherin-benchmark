// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IDuoMaster.sol";

contract TimeLock {
    error NotOwnerError();
    error AlreadyQueuedError(bytes32 txId);
    error TimestampNotInRangeError(uint blockTimestamp, uint timestamp);
    error NotQueuedError(bytes32 txId);
    error TimestampNotPassedError(uint blockTimestmap, uint timestamp);
    error TimestampExpiredError(uint blockTimestamp, uint expiresAt);
    error TxFailedError();

    event Queue(
        bytes32 indexed txId,
        address indexed target,
        uint value,
        string func,
        bytes data,
        uint timestamp
    );
    event Execute(
        bytes32 indexed txId,
        address indexed target,
        uint value,
        string func,
        bytes data,
        uint timestamp
    );
    event Cancel(bytes32 indexed txId);

    uint public MIN_DELAY = 60; // seconds
    uint public MAX_DELAY = 86400; // seconds
    uint public constant GRACE_PERIOD = 604800; // 7 days

    struct DelayQueue {
        uint delayQueueTimeStamp;
        uint delayQueueMin;
        uint delayQueueMax;
    }
    DelayQueue public delayQueue;

    address public owner;
    // tx id => queued
    mapping(bytes32 => bool) public queued;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwnerError();
        }
        _;
    }

    receive() external payable {}

    function queueSetDelay(uint min, uint max) external onlyOwner {
        require(min <= max, "min > max");

        delayQueue.delayQueueMin = min;
        delayQueue.delayQueueMax = max;
        delayQueue.delayQueueTimeStamp = block.timestamp + MIN_DELAY;
    }

    function executeSetDelay() external onlyOwner {
        require(
            block.timestamp >= delayQueue.delayQueueTimeStamp,
            "Delay not passed"
        );

        MIN_DELAY = delayQueue.delayQueueMin;
        MAX_DELAY = delayQueue.delayQueueMax;
    }

    function getTxId(
        address _target,
        uint _value,
        string calldata _func,
        bytes calldata _data,
        uint _timestamp
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_target, _value, _func, _data, _timestamp));
    }

    /**
     * @param _target Address of contract or account to call
     * @param _value Amount of ETH to send
     * @param _func Function signature, for example "foo(address,uint256)"
     * @param _data ABI encoded data send. abiCoder.encode(["address", "uint256"], ["0x123...", 123])
     * @param _timestamp Timestamp after which the transaction can be executed.
     */
    function queue(
        address _target,
        uint _value,
        string calldata _func,
        bytes calldata _data,
        uint _timestamp
    ) external onlyOwner returns (bytes32 txId) {
        txId = getTxId(_target, _value, _func, _data, _timestamp);
        if (queued[txId]) {
            revert AlreadyQueuedError(txId);
        }
        // ---|------------|---------------|-------
        //  block    block + min     block + max
        if (
            _timestamp < block.timestamp + MIN_DELAY ||
            _timestamp > block.timestamp + MAX_DELAY
        ) {
            revert TimestampNotInRangeError(block.timestamp, _timestamp);
        }

        queued[txId] = true;

        emit Queue(txId, _target, _value, _func, _data, _timestamp);
    }

    function execute(
        address _target,
        uint _value,
        string calldata _func,
        bytes calldata _data,
        uint _timestamp
    ) external payable onlyOwner returns (bytes memory) {
        bytes32 txId = getTxId(_target, _value, _func, _data, _timestamp);
        if (!queued[txId]) {
            revert NotQueuedError(txId);
        }
        // ----|-------------------|-------
        //  timestamp    timestamp + grace period
        if (block.timestamp < _timestamp) {
            revert TimestampNotPassedError(block.timestamp, _timestamp);
        }
        if (block.timestamp > _timestamp + GRACE_PERIOD) {
            revert TimestampExpiredError(
                block.timestamp,
                _timestamp + GRACE_PERIOD
            );
        }

        queued[txId] = false;

        // prepare data
        bytes memory data;
        if (bytes(_func).length > 0) {
            // data = func selector + _data
            data = abi.encodePacked(bytes4(keccak256(bytes(_func))), _data);
        } else {
            // call fallback with data
            data = _data;
        }

        // call target
        (bool ok, bytes memory res) = _target.call{value: _value}(data);
        if (!ok) {
            revert TxFailedError();
        }

        emit Execute(txId, _target, _value, _func, _data, _timestamp);

        return res;
    }

    function cancel(bytes32 _txId) external onlyOwner {
        if (!queued[_txId]) {
            revert NotQueuedError(_txId);
        }

        queued[_txId] = false;

        emit Cancel(_txId);
    }

    // @dev add function can execute directly
    function add(
        IDuoMaster _duoMaster,
        uint256 alloc,
        uint16 depositBP,
        uint16 withdrawBP,
        IERC20 want,
        bool withUpdate,
        bool isWithdrawFee,
        IStrategy strat
    ) external onlyOwner {
        _duoMaster.add(
            alloc,
            depositBP,
            withdrawBP,
            want,
            withUpdate,
            isWithdrawFee,
            strat
        );
    }

    // @dev set function can execute directly
    function set(
        IDuoMaster _duoMaster,
        uint256 pid,
        uint256 alloc,
        uint16 depositBP,
        uint16 withdrawBP,
        bool withUpdate,
        bool isWithdrawFee
    ) external onlyOwner {
        _duoMaster.set(
            pid,
            alloc,
            depositBP,
            withdrawBP,
            withUpdate,
            isWithdrawFee
        );
    }
}

