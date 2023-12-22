// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IDiamond} from "./IDiamond.sol";
import {IBeacon} from "./IBeacon.sol";
import {IDiamondCut} from "./IDiamondCut.sol";

// Remember to add the loupe functions from DiamondLoupeBeacon to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

error NoSelectorsGivenToAdd();
error NotContractOwner(address _user, address _contractOwner);
error NoSelectorsProvidedForBeaconForCut(address _beaconAddress);
error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);
error NoBytecodeAtAddress(address _contractAddress, string _message);
error IncorrectBeaconCutAction(uint8 _action);
error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
error CannotReplaceFunctionsFromBeaconWithZeroAddress(bytes4[] _selectors);
error CannotReplaceImmutableFunction(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFunctionFromTheSameBeacon(bytes4 _selector);
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
error RemoveBeaconAddressMustBeZeroAddress(address _beaconAddress);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveImmutableFunction(bytes4 _selector);
error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

library LibDiamond {
    /**
     * @notice Diamond storage position.
     */
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    /**
     * @notice Beacon and Selector position struct.
     */
    struct BeaconAddressAndSelectorPosition {
        address beaconAddress;
        uint16 selectorPosition;
    }

    /**
     * @notice Diamond storage.
     */
    struct DiamondStorage {
        // function selector => beacon address and selector position in selectors array
        mapping(bytes4 => BeaconAddressAndSelectorPosition) beaconAddressAndSelectorPosition;
        bytes4[] selectors;
        mapping(bytes4 => bool) supportedInterfaces;
        // owner of the contract
        address contractOwner;
    }

    /**
     * @notice Get diamond storage.
     */
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SetBeacon(address indexed oldBeacon, address indexed newBeacon);

    /**
     * @notice Set owner.
     */
    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /**
     * @notice Get owner.
     */
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /**
     * @notice If msg.sender not owner revert.
     */
    function enforceIsContractOwner() internal view {
        if (msg.sender != diamondStorage().contractOwner) {
            revert NotContractOwner(msg.sender, diamondStorage().contractOwner);
        }
    }

    event DiamondCut(IDiamondCut.BeaconCut[] _diamondCut, address _init, bytes _calldata);

    /**
     * @notice Procces to Add, replace or Remove Facets.
     */
    function diamondCut(IDiamondCut.BeaconCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
        uint256 length = _diamondCut.length;
        for (uint256 beaconIndex; beaconIndex < length;) {
            bytes4[] memory functionSelectors = _diamondCut[beaconIndex].functionSelectors;
            address beaconAddress = _diamondCut[beaconIndex].beaconAddress;
            if (functionSelectors.length == 0) {
                revert NoSelectorsProvidedForBeaconForCut(beaconAddress);
            }
            IDiamondCut.BeaconCutAction action = _diamondCut[beaconIndex].action;
            if (action == IDiamond.BeaconCutAction.Add) {
                addFunctions(beaconAddress, functionSelectors);
            } else if (action == IDiamond.BeaconCutAction.Replace) {
                replaceFunctions(beaconAddress, functionSelectors);
            } else if (action == IDiamond.BeaconCutAction.Remove) {
                removeFunctions(beaconAddress, functionSelectors);
            } else {
                revert IncorrectBeaconCutAction(uint8(action));
            }
            unchecked {
                ++beaconIndex;
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
    }

    /**
     * @notice Procces to Add Facets.
     */
    function addFunctions(address _beaconAddress, bytes4[] memory _functionSelectors) internal {
        if (_beaconAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }
        DiamondStorage storage ds = diamondStorage();
        uint16 selectorCount = uint16(ds.selectors.length);
        enforceHasContractCode(_beaconAddress, "LibDiamondCut: Add beacon has no code");
        uint256 length = _functionSelectors.length;
        for (uint256 selectorIndex; selectorIndex < length;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldBeaconAddress = ds.beaconAddressAndSelectorPosition[selector].beaconAddress;
            if (oldBeaconAddress != address(0)) {
                revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
            }
            ds.beaconAddressAndSelectorPosition[selector] =
                BeaconAddressAndSelectorPosition(_beaconAddress, selectorCount);
            ds.selectors.push(selector);
            selectorCount++;
            unchecked {
                ++selectorIndex;
            }
        }
    }

    /**
     * @notice Procces to Replace Facets.
     */
    function replaceFunctions(address _beaconAddress, bytes4[] memory _functionSelectors) internal {
        DiamondStorage storage ds = diamondStorage();
        if (_beaconAddress == address(0)) {
            revert CannotReplaceFunctionsFromBeaconWithZeroAddress(_functionSelectors);
        }
        enforceHasContractCode(_beaconAddress, "LibDiamondCut: Replace beacont has no code");
        uint256 length = _functionSelectors.length;
        for (uint256 selectorIndex; selectorIndex < length;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldBeaconAddress = ds.beaconAddressAndSelectorPosition[selector].beaconAddress;
            // can't replace immutable functions -- functions defined directly in the diamond in this case
            if (oldBeaconAddress == address(this)) {
                revert CannotReplaceImmutableFunction(selector);
            }
            if (oldBeaconAddress == _beaconAddress) {
                revert CannotReplaceFunctionWithTheSameFunctionFromTheSameBeacon(selector);
            }
            if (oldBeaconAddress == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExists(selector);
            }
            // replace old beacon address
            ds.beaconAddressAndSelectorPosition[selector].beaconAddress = _beaconAddress;
            unchecked {
                ++selectorIndex;
            }
        }
    }

    /**
     * @notice Procces to Remove Facets.
     */
    function removeFunctions(address _beaconAddress, bytes4[] memory _functionSelectors) internal {
        DiamondStorage storage ds = diamondStorage();
        uint256 selectorCount = ds.selectors.length;
        if (_beaconAddress != address(0)) {
            revert RemoveBeaconAddressMustBeZeroAddress(_beaconAddress);
        }
        uint256 length = _functionSelectors.length;
        for (uint256 selectorIndex; selectorIndex < length;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            BeaconAddressAndSelectorPosition memory oldBeaconAddressAndSelectorPosition =
                ds.beaconAddressAndSelectorPosition[selector];
            if (oldBeaconAddressAndSelectorPosition.beaconAddress == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }

            // can't remove immutable functions -- functions defined directly in the diamond
            if (oldBeaconAddressAndSelectorPosition.beaconAddress == address(this)) {
                revert CannotRemoveImmutableFunction(selector);
            }
            // replace selector with last selector
            selectorCount--;
            if (oldBeaconAddressAndSelectorPosition.selectorPosition != selectorCount) {
                bytes4 lastSelector = ds.selectors[selectorCount];
                ds.selectors[oldBeaconAddressAndSelectorPosition.selectorPosition] = lastSelector;
                ds.beaconAddressAndSelectorPosition[lastSelector].selectorPosition =
                    oldBeaconAddressAndSelectorPosition.selectorPosition;
            }
            // delete last selector
            ds.selectors.pop();
            delete ds.beaconAddressAndSelectorPosition[selector];

            unchecked {
                ++selectorIndex;
            }
        }
    }

    /**
     * @notice Procces to initialize Diamond contract.
     */
    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            return;
        }
        enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                // bubble up error
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    /**
     * @notice Enforce contract.
     */
    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        if (contractSize == 0) {
            revert NoBytecodeAtAddress(_contract, _errorMessage);
        }
    }

    /**
     * @notice get beacon implementation.
     */
    function _implementation() internal view returns (address) {
        return IBeacon(diamondStorage().beaconAddressAndSelectorPosition[msg.sig].beaconAddress).implementation();
    }
}

