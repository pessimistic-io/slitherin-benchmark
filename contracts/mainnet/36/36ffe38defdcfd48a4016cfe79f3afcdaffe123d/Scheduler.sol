// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OpsReady.sol";
import "./GnosisUtils.sol";
import "./AssetRecoverable.sol";
import "./IResolver.sol";
import "./ICollection.sol";
import "./SchedulerStorage.sol";
import "./IScheduler.sol";

/// @title Scheduler
/// @author Chain Labs
/// @notice Create, store and pass execution of schmint between various modules
contract Scheduler is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    OpsReady,
    Module,
    GnosisUtils,
    AssetRecoverable,
    SchedulerStorage
{
    /// @notice name of the contract
    /// @return name of the contract as string
    string public constant NAME = "Scheduler";

    /// @notice version of the contract
    /// @return version of the contract as string
    string public constant VERSION = "0.1.0_beta";

    /// @notice logs when a schmint is successfully executed
    /// @dev emitted when a schmint is executed
    /// @param schmintId id of schmint which was successfully execited
    event SchmintSuccess(uint256 indexed schmintId);

    /// @notice logs when funds are deposited to gnosis safe via scheduler
    /// @dev emitted when funds are transferred to gnosis safe via scheduler
    /// @param depositAmount amount transferred in one transaction
    event FundsDepositedToSafe(uint256 depositAmount);

    /// @notice logs when a schmint is created
    /// @dev emitted when a schmint is created
    /// @param target address of target contract where the schmint should be executed
    /// @param schmintId id of newly created schmint
    /// @param taskId task ID of newly created schmint (task ID is relevant for gelato context)
    event SchmintCreated(
        address indexed target,
        uint256 indexed schmintId,
        bytes32 indexed taskId
    );

    /// @notice logs when a schmint is cancelled
    /// @dev emitted when a schmint is cancelled
    /// @param schmintId ID of the schmint that was cancelled
    event SchmintCancelled(uint256 schmintId);

    /// @notice logs when a schmint is modified
    /// @dev emitted when a schmint is modified
    /// @param schmintId ID of the schmint that was modified
    event SchmintModified(uint256 schmintId);

    /// @notice logs when schmint fee is charged and transferred
    /// @dev emitted when schmint fee is charged and transferred
    /// @param schmintId ID of schmint for which fee was transferred
    /// @param schmintFee amount of schmint fee that was transferred
    /// @param feeReceiver address of schmint fee receiver
    event SchmintFeeTransferred(
        uint256 indexed schmintId,
        uint256 schmintFee,
        address feeReceiver
    );

    modifier schmintActive() {
        _schmintingShouldBeActive();
        _;
    }

    /// @notice constructor
    /// @dev ensure that the master copy cannot be initialized
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initializes the scheduler and makes it ready for use
    /// @dev initializes scheduler, creates new gnosis safe and add schmints if any
    /// @param _owners address of owner
    /// @param _resolver address of simplr's resolver
    /// @param _schmints list of schmints to be added
    function initialize(
        address[] memory _owners,
        address _resolver,
        SchmintInput[] memory _schmints
    ) external payable {
        setUp(abi.encode(_owners, _resolver, _schmints));
    }

    /// @notice setup function, called directly by initializer
    /// @dev using it to support interface
    /// @param initializeParams encoded parameters
    function setUp(bytes memory initializeParams)
        public
        virtual
        override
        initializer
    {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        // decode parameters
        (
            address[] memory _owners,
            address _resolver,
            SchmintInput[] memory _schmints
        ) = abi.decode(initializeParams, (address[], address, SchmintInput[]));

        (
            address _ops,
            address _safeFactory,
            address _singleton,
            address _fallbackHandler
        ) = IResolver(_resolver).setupInputResolver();
        // need to set ops before creating schmint
        __OpsReadyInit(_ops);

        _owners[1] = address(this);
        // create safe
        GnosisSafe safe = _createSafe(
            _owners,
            _safeFactory,
            _singleton,
            _fallbackHandler
        );

        // enable module
        _enableModule(safe);
        avatar = address(safe);
        target = address(safe);

        // remove this module from owner
        _removeOwner(safe, _owners);

        // set resolver
        resolver = _resolver;

        // create schmint
        if (_schmints.length > 0) {
            _createSchmint(_schmints);
        }

        _transferOwnership(_owners[0]);
        _checkDepositAndTransferToSafe();
    }

    /// @notice create schmints
    /// @dev create multiple schmint at a time, funds can be transferred to gnosis safe as well
    /// @param schmintInputs list of schmint to be created
    function createSchmint(SchmintInput[] memory schmintInputs)
        external
        payable
        onlyOwner
        schmintActive
    {
        _createSchmint(schmintInputs);
        _checkDepositAndTransferToSafe();
    }

    /// @notice create schmint
    /// @dev loops over list of schmint and create schmint
    /// @param schmintInputs list of schmints to be created
    function _createSchmint(SchmintInput[] memory schmintInputs) internal {
        for (uint256 i; i < schmintInputs.length; i++) {
            _createSchmint(
                schmintInputs[i].target,
                schmintInputs[i].data,
                schmintInputs[i].value,
                schmintInputs[i].gasPriceLimit
            );
        }
    }

    /// @notice create schmint
    /// @dev create schmint and add task in gelato
    /// @param _target address of target contract
    /// @param _data encoded function selector with parameters making up data for the function call at target
    /// @param _value amount of native token to be transferred to target
    /// @param _gasPriceLimit maximum limit of gas price
    function _createSchmint(
        address _target,
        bytes memory _data,
        uint256 _value,
        uint40 _gasPriceLimit
    ) internal {
        // schmint IDs start from 0
        uint256 schmintId = schmintCounter;

        // preparing execData, this is passed to executeSchmint method
        bytes memory execData = abi.encodeWithSelector(
            this.executeSchmint.selector,
            schmintId
        );
        // preparing resolver data, this is passed to checker method and returned as it is, without any modification
        bytes memory resolverData = abi.encodeWithSelector(
            this.checker.selector,
            execData
        );

        bytes32 taskId;
        // scoping creation of task
        {
            // create schmint task
            taskId = IOps(ops).createTaskNoPrepayment(
                address(this),
                this.executeSchmint.selector,
                address(this),
                resolverData,
                ETH
            );
        }

        // scoping writing of schmint to storage
        {
            // store schmint
            schmints[schmintId] = Schmint({
                taskId: taskId,
                target: _target,
                data: _data,
                value: _value,
                gasPriceLimit: _gasPriceLimit,
                isSchminted: false,
                isCancelled: false
            });
        }

        unchecked {
            schmintCounter = schmintId + 1;
        }

        // emit event when schmint created
        emit SchmintCreated(_target, schmintId, taskId);
    }

    /// @notice edit schmint
    /// @dev edit multiple arguments of the schmint
    /// @param _schmintId ID of schmint which needs to be edited
    /// @param _newValue new value argument
    /// @param _gasPriceLimit new maximum gas price limit
    /// @param _newData new data
    function modifySchmint(
        uint256 _schmintId,
        uint256 _newValue,
        uint40 _gasPriceLimit,
        bytes memory _newData
    ) external payable onlyOwner {
        Schmint storage _schmint = schmints[_schmintId];
        if (_schmint.taskId == bytes32(0)) {
            revert SchmintNotExist();
        }
        _checkSchmintNotExecutedNorCancelled(_schmint);
        _schmint.data = _newData;
        _schmint.value = _newValue;
        _schmint.gasPriceLimit = _gasPriceLimit;
        _checkDepositAndTransferToSafe();
        emit SchmintModified(_schmintId);
    }

    /// @notice cancel a schmint
    /// @dev cancel schmint and also cancel task from gelato
    /// @param _schmintId ID of schmint which needs to be cancelled
    function cancelSchmint(uint256 _schmintId) external onlyOwner {
        Schmint storage _schmint = schmints[_schmintId];
        _checkSchmintNotExecutedNorCancelled(_schmint);
        IOps(ops).cancelTask(_schmint.taskId);
        _schmint.isCancelled = true;
        emit SchmintCancelled(_schmintId);
    }

    /// @notice execute schmint
    /// @dev schmint can only be executed by OPs contract
    /// @param schmintId ID of schmint which needs to be executed
    function executeSchmint(uint256 schmintId) external nonReentrant onlyOps {
        // read schmint
        Schmint storage schmint = schmints[schmintId];

        // scoping checks into one block
        {
            if (schmint.target == address(0)) {
                revert SchmintNotExist();
            }
            _checkSchmintNotExecutedNorCancelled(schmint);

            // check if gas price is within gas price limit
            if (
                schmint.gasPriceLimit > 0 && tx.gasprice > schmint.gasPriceLimit
            ) {
                revert GasPriceExceedsLimit(tx.gasprice, schmint.gasPriceLimit);
            }
        }

        // set schmint as executed
        schmint.isSchminted = true;

        // increment schmintExecuted when a schmint is executed
        unchecked {
            schmintsExecuted++;
        }

        // scoping external call to one block
        {
            // execute schmint
            bool success = exec(
                schmint.target,
                schmint.value,
                schmint.data,
                Enum.Operation.Call
            );
            // if schmint success,
            if (!success) {
                // revert with error - Schmint failed
                revert SchmintFailed();
            }
        }

        {
            // get fee and transfer fee
            (uint256 schmintFee, address feeReceiver) = IResolver(resolver)
                .calculateFee(schmintsExecuted, owner());
            // if fee > 0 and fee receiver is not zero address
            if (schmintFee > 0 && feeReceiver != address(0)) {
                // then
                // transfer fee
                exec(feeReceiver, schmintFee, "", Enum.Operation.Call);
                emit SchmintFeeTransferred(schmintId, schmintFee, feeReceiver);
            }
        }

        // scoping transaction fee transfer into one block
        {
            // prepare for transferring transaction fee
            uint256 transactionFee;
            address feeToken;

            // fetch the transaction cost and token to be used to pay fee
            (transactionFee, feeToken) = IOps(ops).getFeeDetails();

            // transfer transaction cost
            _transfer(transactionFee, feeToken);
        }
        // emit TokenSchminted
        emit SchmintSuccess(schmintId);
    }

    /// @notice check if the schmint is executable or not
    /// @dev check if schmint is active or not and returns the execution data as it is
    /// @param execData execute data to be passed to executeSchmint parameter
    /// @return is schmint active and ready to be executed
    /// @return data to be used to invoke executeSchmint
    function checker(bytes memory execData)
        external
        view
        schmintActive
        returns (bool, bytes memory)
    {
        return (true, execData);
    }

    /// @notice recover stuck ERC20
    /// @param _erc20 address of erc20 token contract
    /// @param _receiver receiver address
    /// @param _amount amount of token to be recovered
    function recoverERC20(
        address _erc20,
        address _receiver,
        uint256 _amount
    ) public onlyOwner nonReentrant {
        _recoverERC20(_erc20, _receiver, _amount);
    }

    /// @notice recover stuck ERC721 tokens
    /// @param _erc721 address of erc721 token contract
    /// @param _receiver receiver address
    /// @param _id ID of ERC721 token to be recovered
    function recoverERC721(
        address _erc721,
        address _receiver,
        uint256 _id
    ) public onlyOwner nonReentrant {
        _recoverERC721(_erc721, _receiver, _id);
    }

    /// @notice recover stuck ERC1155 tokens
    /// @param _erc1155 address of erc1155 token contract
    /// @param _receiver receiver address
    /// @param _id ID of ERC1155 token to be recovered
    /// @param _amount amount of ERC1155's ID token to be recovered
    function recoverERC1155(
        address _erc1155,
        address _receiver,
        uint256 _id,
        uint256 _amount
    ) public onlyOwner nonReentrant {
        _recoverERC1155(_erc1155, _receiver, _id, _amount);
    }

    /// @notice ensure the Scheduler contract cannot receiver any native token
    receive() external payable {
        revert NoFundsShouldBeTransferred();
    }

    /// @notice check and deposit funds to gnosis safe if any funds deposited
    function _checkDepositAndTransferToSafe() internal {
        if (msg.value > 0) {
            AddressUpgradeable.sendValue(payable(avatar), msg.value);
            emit FundsDepositedToSafe(msg.value);
        }
    }

    /// @notice transfer transaction fee to executor of schmint
    /// @param _amount amount of tokens to be transferred to cover transaction fee
    /// @param _paymentToken token address
    function _transfer(uint256 _amount, address _paymentToken)
        internal
        virtual
        override
    {
        if (_paymentToken == ETH) {
            bool success = exec(gelato, _amount, "", Enum.Operation.Call);
            if (!success) {
                revert TransferOfTransactionFeeFailed();
            }
        } else {
            bytes memory execData = abi.encodeWithSelector(
                IERC20.transfer.selector,
                gelato,
                _amount
            );
            exec(_paymentToken, 0, execData, Enum.Operation.Call);
        }
    }

    /// @notice checks if schminting is active or not
    /// @dev resolver stores the flag
    function _schmintingShouldBeActive() internal view {
        if (!IResolver(resolver).isActive()) {
            revert SchmintingInactive();
        }
    }

    /// @notice ensure a schmint is not already executed
    /// @param _schmint schmint
    function _checkSchmintNotExecutedNorCancelled(Schmint memory _schmint)
        internal
        pure
    {
        // ensure the schmint is not executed
        // cannot cancel schmint which is executed
        if (_schmint.isSchminted) {
            revert AlreadyExecuted();
        }
        // ensure the schmint is not cancelled
        // cannot cancel schmint that is already cancelled
        if (_schmint.isCancelled) {
            revert AlreadyCancelled();
        }
    }
}

