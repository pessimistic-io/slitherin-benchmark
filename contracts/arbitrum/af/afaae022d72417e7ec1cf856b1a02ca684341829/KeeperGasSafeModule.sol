pragma solidity ^0.8.17;

import {GnosisSafe} from "./GnosisSafe.sol";
import {Enum} from "./Enum.sol";

contract KeeperGasSafeModule {
    error OnlyOwner();
    error OnlyNotPaused();
    error DistributionRateLimit();
    error BalanceGreaterThanMin();
    event GasDistributed(
        uint _amountDistributed
    );
    event Paused();
    event Unpaused();
    event KeeperUpdated(address _oldKeeper, address _newKeeper);

    address public immutable OWNER;
    GnosisSafe public immutable DELEGATOR;
    uint public immutable DISTRIBUTION_AMOUNT;
    uint public immutable MIN_DISTRIBUTION_TIME;

    address public keeper;
    uint public lastGasDistribution;
    uint public minGasBalance;
    bool public isPaused;

    constructor(address _owner, GnosisSafe _delegator, uint _distAmount, address _keeper, uint _minDistributionTime) {
        OWNER = _owner;
        DELEGATOR = _delegator;
        DISTRIBUTION_AMOUNT = _distAmount;
        keeper = _keeper;
        MIN_DISTRIBUTION_TIME = _minDistributionTime;
        isPaused = false;
        lastGasDistribution = block.timestamp;
    }

    function distributeGas()
        external
        onlyNotPaused
    {
        if (block.timestamp < lastGasDistribution + MIN_DISTRIBUTION_TIME) 
            revert DistributionRateLimit();

        if (keeper.balance > minGasBalance) 
            revert BalanceGreaterThanMin();

        lastGasDistribution = block.timestamp;

        _sendEth(keeper, DISTRIBUTION_AMOUNT);

        emit GasDistributed(DISTRIBUTION_AMOUNT);
    }

    function setMinGasBalance(uint _newMinBalance) external onlyOwner {
        require(_newMinBalance < 1 ether, "!above threshold");
        minGasBalance = _newMinBalance;
    }

    function setIsPaused(bool _isPaused) external onlyOwner {
        isPaused = _isPaused;
        if (_isPaused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    function setKeeper(address _newKeeper) external onlyOwner {
        require(_newKeeper != address(0));
        emit KeeperUpdated(keeper, _newKeeper);
        keeper = _newKeeper;
    }

    function _sendEth(
        address _to,
        uint _amount
    ) internal returns (bytes memory _ret) {
        bool success;
        (success, _ret) = DELEGATOR.execTransactionFromModuleReturnData(
            _to,
            _amount,
            bytes(""),
            Enum.Operation.Call
        );
        if (!success) {
            /// @solidity memory-safe-assembly
            assembly {
                revert(add(_ret, 0x20), mload(_ret))
            }
        }
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert OnlyOwner();
        }
        _;
    }

    modifier onlyNotPaused() {
        if (isPaused) {
            revert OnlyNotPaused();
        }
        _;
    }
}

