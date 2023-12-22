pragma solidity 0.8.19;

import {Safe} from "./Safe.sol";
import {Enum} from "./Enum.sol";
import {ModuleManager} from "./ModuleManager.sol";

contract MevModule {
    error OnlySafe();
    error OnlyAdmin();
    error OnlyExecutor();
    error OnlyWhitelistedContract();
    error InvalidData();

    event ExecutorAdded(address _executor);
    event ExectuorRemoed(address _executor);
    event ContractAdded(address _contract, Enum.Operation _operation);
    event ContractRemoved(address _contract, Enum.Operation _operation);

    ModuleManager public immutable SAFE;
    mapping(address => bool) public isExecutor;
    mapping(address => bool) public isWhitelistedContractCall;
    mapping(address => bool) public isWhitelistedContractDelegateCall;

    constructor(ModuleManager _safe) {
        SAFE = _safe;
    }

    function addExecutor(address _executor) external onlySafe {
        isExecutor[_executor] = true;
        emit ExecutorAdded(_executor);
    }

    function removeExecutor(address _executor) external onlySafe {
        isExecutor[_executor] = false;
        emit ExectuorRemoed(_executor);
    }

    function addContract(
        address _contract,
        Enum.Operation _operation
    ) external onlySafe {
        if (_operation == Enum.Operation.Call) {
            isWhitelistedContractCall[_contract] = true;
        } else if (_operation == Enum.Operation.DelegateCall) {
            isWhitelistedContractDelegateCall[_contract] = true;
        } else {
            revert InvalidData();
        }
        emit ContractAdded(_contract, _operation);
    }

    function removeContract(
        address _contract,
        Enum.Operation _operation
    ) external onlySafe {
        if (_operation == Enum.Operation.Call) {
            isWhitelistedContractCall[_contract] = false;
        } else if (_operation == Enum.Operation.DelegateCall) {
            isWhitelistedContractDelegateCall[_contract] = false;
        } else {
            revert InvalidData();
        }
        emit ContractRemoved(_contract, _operation);
    }

    function call(
        address _target,
        bytes calldata _data,
        uint256 _value
    ) external payable onlySafe returns (bool _success, bytes memory _ret) {
        (_success, _ret) = _target.call{value: _value}(_data);
    }

    function dcall(
        address _target,
        bytes calldata _data
    ) external payable onlySafe returns (bool _success, bytes memory _ret) {
        (_success, _ret) = _target.delegatecall(_data);
    }

    modifier onlySafe() {
        if (msg.sender != address(SAFE)) revert OnlySafe();
        _;
    }

    modifier onlyExecutor() {
        if (!isExecutor[msg.sender]) revert OnlyExecutor();
        _;
    }

    modifier onlyWhitelisted(address _to, Enum.Operation _operation) {
        if (_operation == Enum.Operation.Call) {
            if (!isWhitelistedContractCall[_to])
                revert OnlyWhitelistedContract();
        } else if (_operation == Enum.Operation.DelegateCall) {
            if (!isWhitelistedContractDelegateCall[_to])
                revert OnlyWhitelistedContract();
        } else {
            revert InvalidData();
        }
        _;
    }

    function execCall(
        address _to,
        bytes calldata _data
    ) external returns (bytes memory _ret) {
        _ret = _exec(_to, 0, _data, Enum.Operation.Call);
    }

    function execCallWithValue(
        address _to,
        bytes calldata _data,
        uint _value
    ) external returns (bytes memory _ret) {
        _ret = _exec(_to, _value, _data, Enum.Operation.Call);
    }

    function execDelegateCall(address _to, bytes calldata _data) external {
        _exec(_to, 0, _data, Enum.Operation.DelegateCall);
    }

    function execDelegateCallWithValue(
        address _to,
        bytes calldata _data,
        uint _value
    ) external {
        _exec(_to, _value, _data, Enum.Operation.DelegateCall);
    }

    function _exec(
        address _to,
        uint _value,
        bytes calldata _data,
        Enum.Operation _operation
    ) internal returns (bytes memory _ret) {
        if (!isExecutor[msg.sender]) revert OnlyExecutor();
        if (_operation == Enum.Operation.Call) {
            if (!isWhitelistedContractCall[_to])
                revert OnlyWhitelistedContract();
        } else if (_operation == Enum.Operation.DelegateCall) {
            if (!isWhitelistedContractDelegateCall[_to])
                revert OnlyWhitelistedContract();
        } else {
            revert InvalidData();
        }

        bool success;
        if (_operation == Enum.Operation.Call) {
            (success, _ret) = SAFE.execTransactionFromModuleReturnData(
                _to,
                _value,
                _data,
                Enum.Operation.Call
            );
        } else if (_operation == Enum.Operation.DelegateCall) {
            (success, _ret) = SAFE.execTransactionFromModuleReturnData(
                _to,
                _value,
                _data,
                Enum.Operation.DelegateCall
            );
        } else {
            revert InvalidData();
        }

        if (!success) {
            assembly {
                revert(add(_ret, 0x20), mload(_ret))
            }
        }
    }

    // receive() external payable {}

    //     fallback() external payable {
    //         _checkMessageLength(1);

    //         uint8 selector = uint8(msg.data[0]);
    //         if (selector == 0) {
    //             _checkMessageLength(21);
    //             address target = address(bytes20(msg.data[1:21]));
    //             bytes memory data;
    //             assembly {
    //                 data := mload(0x40)
    //                 let size := sub(calldatasize(), 21)
    //                 mstore(data, size)
    //                 calldatacopy(add(data, 0x20), 21, size)
    //             }
    //         }
    //     }

    //     function _checkMessageLength(uint256 _length) internal pure {
    //         if (msg.data.length < _length) revert InvalidData();
    //     }

    //     function _call(
    //         address _target,
    //         bytes memory _data,
    //         uint256 _value
    //     ) internal returns (bytes memory _ret) {
    //         bool success;
    //         (success, _ret) = _target.call{value: _value}(_data);
    //         if (!success) {
    //             assembly {
    //                 revert(add(_ret, 0x20), mload(_ret))
    //             }
    //         }
    //     }

    //     function _dcall(
    //         address _target,
    //         bytes memory _data
    //     ) internal returns (bytes memory _ret) {
    //         bool success;
    //         (success, _ret) = _target.delegatecall(_data);
    //         if (!success) {
    //             assembly {
    //                 revert(add(_ret, 0x20), mload(_ret))
    //             }
    //         }
    //     }
}

