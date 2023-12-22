// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AccessControl.sol";

/**
 * @dev Contract module which acts as a timelocked controller. When set as the
 * owner of an `Ownable` smart contract, it enforces a timelock on all
 * `onlyOwner` maintenance operations. This gives time for users of the
 * controlled contract to exit before a potentially dangerous maintenance
 * operation is applied.
 *
 * By default, this contract is self administered, meaning administration tasks
 * have to go through the timelock process. The proposer (resp executor) role
 * is in charge of proposing (resp executing) operations. A common use case is
 * to position this {TimelockController} as the owner of a smart contract, with
 * a multisig or a DAO as the sole proposer.
 *
 * _Available since v3.3._
 */
contract TimelockController is AccessControl {
    bytes32 public constant TIMELOCK_ADMIN_ROLE =
        keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant VETO_ROLE = keccak256("VETO_ROLE");
    bytes32 public constant SUPREMECOURT_ROLE = keccak256("SUPREMECOURT_ROLE");
    bytes32 public constant CANCELLOR_ROLE = keccak256("CANCELLOR_ROLE");

    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

    mapping(bytes32 => uint256) private _timestamps;

    uint256 private _minDelay;

    /**
     * @dev disputed is mapping which tells if the operation is disputed or can be disputed.
     * 0 => is not disputed and can be disputed
     * 1 => disputed
     * 2 => not disputed and can not be disputed, needed as if an operation is disputed once and
     *      supreme court rejects it, it can not be disputed again.
     */
    mapping(bytes32 => uint16) public _disputed;

    /**
     * @dev Emitted when a call is scheduled as part of operation `id`.
     */
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 readyTime,
        address sender,
        string status
    );

    /**
     * @dev Emitted when a call is performed as part of operation `id`.
     */
    event CallExecuted(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        address sender,
        string status
    );

    /**
     * @dev Emitted when operation `id` is cancelled.
     */
    event Cancelled(bytes32 indexed id, address sender, string status);

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);

    /**
     * @dev Emitted when an operation `id` is disputed by VETO
     */
    event CallDisputed(bytes32 indexed id, address sender, string status);

    /**
     * @dev Emitted when a disputed operation `id` is resolved by SUPREMECOURT
     */
    event CallDisputedResolved(
        bytes32 indexed id,
        bool ruling,
        bytes data,
        address sender,
        string status
    );

    /**
     * @dev Initializes the contract with a given `minDelay`.
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address[] memory vetos,
        address[] memory supremecourts,
        address[] memory cancellors
    ) {
        _setRoleAdmin(TIMELOCK_ADMIN_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(VETO_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(SUPREMECOURT_ROLE, TIMELOCK_ADMIN_ROLE);
        _setRoleAdmin(CANCELLOR_ROLE, TIMELOCK_ADMIN_ROLE);
        // deployer + self administration
        _setupRole(TIMELOCK_ADMIN_ROLE, _msgSender());
        _setupRole(TIMELOCK_ADMIN_ROLE, address(this));

        // register proposers
        for (uint256 i = 0; i < proposers.length; ++i) {
            _setupRole(PROPOSER_ROLE, proposers[i]);
        }

        // register executors
        for (uint256 i = 0; i < executors.length; ++i) {
            _setupRole(EXECUTOR_ROLE, executors[i]);
        }

        // register vetos
        for (uint256 i = 0; i < vetos.length; ++i) {
            _setupRole(VETO_ROLE, vetos[i]);
        }

        // register supremecourts
        for (uint256 i = 0; i < supremecourts.length; ++i) {
            _setupRole(SUPREMECOURT_ROLE, supremecourts[i]);
        }

        // register cancellors
        for (uint256 i = 0; i < cancellors.length; ++i) {
            _setupRole(CANCELLOR_ROLE, cancellors[i]);
        }

        _minDelay = minDelay;
        emit MinDelayChange(0, minDelay);
    }

    /**
     * @dev Modifier to make a function callable only by a certain role. In
     * addition to checking the sender's role, `address(0)` 's role is also
     * considered. Granting a role to `address(0)` is equivalent to enabling
     * this role for everyone.
     */
    modifier onlyRoleOrOpenRole(bytes32 role) {
        if (!hasRole(role, address(0))) {
            _checkRole(role, _msgSender());
        }
        _;
    }

    /**
     * @dev Contract might receive/hold ETH as part of the maintenance process.
     */
    receive() external payable {}

    function getDisputeStatus(bytes32 id)
        public
        view
        returns (uint16 disputed)
    {
        return _disputed[id];
    }

    /**
     * @dev Returns whether an id correspond to a registered operation. This
     * includes both Pending, Ready and Done operations.
     */
    function isOperation(bytes32 id)
        public
        view
        virtual
        returns (bool pending)
    {
        return getTimestamp(id) > 0;
    }

    /**
     * @dev Returns whether an operation is pending or not.
     */
    function isOperationPending(bytes32 id)
        public
        view
        virtual
        returns (bool pending)
    {
        return getTimestamp(id) > _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns whether an operation is ready or not.
     */
    function isOperationReady(bytes32 id)
        public
        view
        virtual
        returns (bool ready)
    {
        uint256 timestamp = getTimestamp(id);
        return timestamp > _DONE_TIMESTAMP && timestamp <= block.timestamp;
    }

    /**
     * @dev Returns whether an operation is done or not.
     */
    function isOperationDone(bytes32 id)
        public
        view
        virtual
        returns (bool done)
    {
        return getTimestamp(id) == _DONE_TIMESTAMP;
    }

    /**
     * @dev Returns the timestamp at with an operation becomes ready (0 for
     * unset operations, 1 for done operations).
     */
    function getTimestamp(bytes32 id)
        public
        view
        virtual
        returns (uint256 timestamp)
    {
        return _timestamps[id];
    }

    /**
     * @dev Returns the minimum delay for an operation to become valid.
     *
     * This value can be changed by executing an operation that calls `updateDelay`.
     */
    function getMinDelay() public view virtual returns (uint256 duration) {
        return _minDelay;
    }

    /**
     * @dev Returns the identifier of an operation containing a single
     * transaction.
     */
    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32 hash) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /**
     * @dev Returns the identifier of an operation containing a batch of
     * transactions.
     */
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32 hash) {
        return keccak256(abi.encode(targets, values, datas, predecessor, salt));
    }

    /**
     * @dev Schedule an operation containing a single transaction.
     *
     * Emits a {CallScheduled} event.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function schedule(
        address target,
        uint256 value,
        // string calldata signature,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit CallScheduled(
            id,
            0,
            target,
            value,
            data,
            predecessor,
            getTimestamp(id),
            msg.sender,
            "Proposed"
        );
    }

    /**
     * @dev Schedule an operation containing a batch of transactions.
     *
     * Emits one {CallScheduled} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'proposer' role.
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        // string[] calldata signatures,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual onlyRole(PROPOSER_ROLE) {
        require(
            targets.length == values.length,
            "TimelockController: length mismatch"
        );
        require(
            targets.length == datas.length,
            "TimelockController: length mismatch"
        );

        bytes32 id = hashOperationBatch(
            targets,
            values,
            datas,
            predecessor,
            salt
        );
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit CallScheduled(
                id,
                i,
                targets[i],
                values[i],
                datas[i],
                predecessor,
                getTimestamp(id),
                msg.sender,
                "Proposed"
            );
        }
    }

    /**
     * @dev Schedule an operation that is to becomes valid after a given delay.
     */
    function _schedule(bytes32 id, uint256 delay) private {
        require(
            !isOperation(id),
            "TimelockController: operation already scheduled"
        );
        require(
            delay >= getMinDelay(),
            "TimelockController: insufficient delay"
        );
        _timestamps[id] = block.timestamp + delay;
    }

    /**
     * @dev Cancel an operation.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function cancel(bytes32 id) public virtual onlyRole(CANCELLOR_ROLE) {
        require(
            isOperationPending(id),
            "TimelockController: operation cannot be cancelled"
        );
        delete _timestamps[id];

        emit Cancelled(id, msg.sender, "Cancelled");
    }

    /**
     * @dev Execute an (ready) operation containing a single transaction.
     *
     * Emits a {CallExecuted} event.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _beforeCall(id, predecessor);
        _call(id, 0, target, value, data);
        _afterCall(id);
    }

    /**
     * @dev Execute an (ready) operation containing a batch of transactions.
     *
     * Emits one {CallExecuted} event per transaction in the batch.
     *
     * Requirements:
     *
     * - the caller must have the 'executor' role.
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        require(
            targets.length == values.length,
            "TimelockController: length mismatch"
        );
        require(
            targets.length == datas.length,
            "TimelockController: length mismatch"
        );

        bytes32 id = hashOperationBatch(
            targets,
            values,
            datas,
            predecessor,
            salt
        );
        _beforeCall(id, predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            _call(id, i, targets[i], values[i], datas[i]);
        }
        _afterCall(id);
    }

    /**
     * @dev Checks before execution of an operation's calls.
     */
    function _beforeCall(bytes32 id, bytes32 predecessor) private view {
        require(
            isOperationReady(id),
            "TimelockController: operation is not ready"
        );
        require(
            getDisputeStatus(id) != 1,
            "TimelockController: operation is disputed so it can not be executed"
        );
        require(
            predecessor == bytes32(0) || isOperationDone(predecessor),
            "TimelockController: missing dependency"
        );
    }

    /**
     * @dev Checks after execution of an operation's calls.
     */
    function _afterCall(bytes32 id) private {
        require(
            isOperationReady(id),
            "TimelockController: operation is not ready"
        );
        _timestamps[id] = _DONE_TIMESTAMP;
    }

    /**
     * @dev Execute an operation's call.
     *
     * Emits a {CallExecuted} event.
     */
    function _call(
        bytes32 id,
        uint256 index,
        address target,
        uint256 value,
        bytes calldata data
    ) private {
        (bool success, ) = target.call{value: value}(data);
        require(success, "TimelockController: underlying transaction reverted");

        emit CallExecuted(
            id,
            index,
            target,
            value,
            data,
            msg.sender,
            "Executed"
        );
    }

    /**
     * @dev Changes the minimum timelock duration for future operations.
     *
     * Emits a {MinDelayChange} event.
     *
     * Requirements:
     *
     * - the caller must be the timelock itself. This can only be achieved by scheduling and later executing
     * an operation where the timelock is the target and the data is the ABI-encoded call to this function.
     */
    function updateDelay(uint256 newDelay) external virtual {
        require(
            msg.sender == address(this),
            "TimelockController: caller must be timelock"
        );
        emit MinDelayChange(_minDelay, newDelay);
        _minDelay = newDelay;
    }

    /**
     * @dev callDispute to pause an (pending) operation .
     *
     * Requirements:
     *
     * - the caller must have the 'veto' role.
     */
    function callDispute(bytes32 id) public virtual onlyRole(VETO_ROLE) {
        require(
            isOperationPending(id),
            "TimelockController: operation is either done or does not exist, can not be disputed"
        );
        require(
            getDisputeStatus(id) == 0,
            "TimelockController: operation is either already disputed or can not be disputed"
        );
        _disputed[id] = 1;
        emit CallDisputed(id, msg.sender, "Vetoed");
    }

    /**
     * @dev callDisputeResolve to (cancel or execute) a disputed operation based on supreme court judgement .
     * @param id operation id
     * @param ruling is judgement returned from supreme court contract, true means veto is successful
     * @param data is for arbitrary data input that may be added for notes purposes (perhaps a hash of data or IPFS content hash).
     *
     * Requirements:
     *
     * - the caller must have the 'supremecourt' role.
     */
    function callDisputeResolve(
        bytes32 id,
        bool ruling,
        bytes calldata data
    ) public onlyRole(SUPREMECOURT_ROLE) {
        require(
            getDisputeStatus(id) == 1,
            "TimelockController: operation is not disputed"
        );
        if (ruling) {
            delete _timestamps[id];
            emit Cancelled(id, msg.sender, "Cancelled");
        } else {
            _disputed[id] = 2;
        }
        emit CallDisputedResolved(
            id,
            ruling,
            data,
            msg.sender,
            "Veto Resolved"
        );
    }
}

