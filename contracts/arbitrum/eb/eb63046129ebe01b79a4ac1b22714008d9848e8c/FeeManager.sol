// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {SafeOwnable} from "./SafeOwnable.sol";

import {IFeeManager} from "./IFeeManager.sol";
import {IFeeBank, FeeBank} from "./FeeBank.sol";
import {Address} from "./Address.sol";

/**
 * @title Fee Manager
 * @author Trader Joe
 * @notice This contract allows to let the fee bank contract to delegate call to any contract without
 * any risk of overwriting the storage variables of the fee bank contract.
 */
contract FeeManager is SafeOwnable, IFeeManager {
    using Address for address;

    IFeeBank internal immutable _FEE_BANK;

    uint256 internal _verifiedRound;
    mapping(address => Component) private _components;

    /**
     * @dev Modifier to check if the caller is a verified component operator of a verified component.
     */
    modifier onlyVerifiedComponentOperator(address component) {
        Component storage _component = _components[component];

        uint256 round = _component.verifiedRound;

        if (round == 0) revert FeeManager__ComponentNotVerified();
        if (_component.operators[msg.sender] != round) revert FeeManager__OnlyComponentOperator();

        _;
    }

    /**
     * @dev Constructor that creates the fee bank.
     */
    constructor() {
        _FEE_BANK = new FeeBank();
    }

    /**
     * @notice Returns the fee bank address.
     * @return The fee bank address.
     */
    function getFeeBank() external view override returns (IFeeBank) {
        return _FEE_BANK;
    }

    /**
     * @notice Returns whether a component is verified.
     * @param component The component address.
     * @return Whether the component is verified, true if verified, false otherwise.
     */
    function isVerifiedComponent(address component) external view override returns (bool) {
        return _components[component].verifiedRound > 0;
    }

    /**
     * @notice Returns whether an operator is allowed to call a component.
     * @param component The component address.
     * @param operator The operator address.
     * @return Whether the operator is allowed to call the component, true if allowed, false otherwise.
     */
    function isComponentOperator(address component, address operator) external view override returns (bool) {
        Component storage _component = _components[component];

        uint256 round = _component.verifiedRound;
        return round > 0 && _component.operators[operator] == round;
    }

    /**
     * @notice Return the result of multiple static calls to different contracts.
     * @param targets The target contracts.
     * @param data The data to static call.
     * @return results The return data from the static calls.
     */
    function batchStaticCall(address[] calldata targets, bytes[] calldata data)
        external
        view
        override
        returns (bytes[] memory results)
    {
        if (targets.length != data.length) revert FeeManager__InvalidLength();

        results = new bytes[](targets.length);

        for (uint256 i; i < targets.length;) {
            (bool success, bytes memory result) = targets[i].staticcall(data[i]);

            unchecked {
                if (success) results[i++] = result;
            }
        }
    }

    /**
     * @notice Verifies a component.
     * @dev Only callable by the owner.
     * @param component The component address.
     */
    function verifyComponent(address component) external override onlyOwner {
        if (component == address(_FEE_BANK)) revert FeeManager__FeeBankIsNotAComponent();

        Component storage _component = _components[component];

        uint256 round = _component.verifiedRound;

        if (round > 0) revert FeeManager__ComponentAlreadyVerified();

        uint256 verifiedRound = ++_verifiedRound;
        _component.verifiedRound = verifiedRound;

        emit ComponentVerified(component, verifiedRound);
    }

    /**
     * @notice Unverifies a component.
     * @dev Only callable by the owner.
     * @param component The component address.
     */
    function unverifyComponent(address component) external override onlyOwner {
        Component storage _component = _components[component];

        if (_component.verifiedRound == 0) revert FeeManager__ComponentNotVerified();

        _component.verifiedRound = 0;

        emit ComponentUnverified(component);
    }

    /**
     * @notice Adds an operator to a component.
     * @dev Only callable by the owner.
     * @param component The component address.
     * @param operator The operator address.
     */
    function addComponentOperator(address component, address operator) external override onlyOwner {
        Component storage _component = _components[component];

        uint256 round = _component.verifiedRound;

        if (round == 0) revert FeeManager__ComponentNotVerified();
        if (_component.operators[operator] == round) revert FeeManager__ComponentOperatorAlreadyAdded();

        _component.operators[operator] = round;

        emit ComponentOperatorAdded(component, operator, round);
    }

    /**
     * @notice Removes an operator from a component.
     * @dev Only callable by the owner.
     * @param component The component address.
     * @param operator The operator address.
     */
    function removeComponentOperator(address component, address operator) external override onlyOwner {
        Component storage _component = _components[component];

        uint256 round = _component.verifiedRound;
        if (round == 0) revert FeeManager__ComponentNotVerified();
        if (_component.operators[operator] != round) revert FeeManager__ComponentOperatorNotAdded();

        _component.operators[operator] = 0;

        emit ComponentOperatorRemoved(component, operator);
    }

    /**
     * @notice Calls a component and returns the result.
     * @dev Only callable by a verified component operator.
     * @param component The component address.
     * @param data The data to call the component with.
     * @return The result of the call.
     */
    function callComponent(address component, bytes calldata data) external override returns (bytes memory) {
        return _callComponent(component, data);
    }

    /**
     * @notice Calls multiple components and returns the results.
     * @dev Only callable by a verified operator of each component.
     * @param components The component addresses.
     * @param data The data to call the components with.
     * @return The results of the calls.
     */
    function callComponents(address[] calldata components, bytes[] calldata data)
        external
        override
        returns (bytes[] memory)
    {
        if (components.length != data.length) revert FeeManager__InvalidLength();

        bytes[] memory results = new bytes[](components.length);

        for (uint256 i; i < components.length;) {
            results[i] = _callComponent(components[i], data[i]);

            unchecked {
                ++i;
            }
        }

        return results;
    }

    /**
     * @notice Calls a contract `target` with `data` and returns the result.
     * @dev Only callable by the owner.
     * @param target The target contract address.
     * @param data The data to call the contract with.
     * @return returnData The result of the call.
     */
    function directCall(address target, bytes calldata data)
        external
        override
        onlyOwner
        returns (bytes memory returnData)
    {
        if (data.length == 0) {
            target.sendValue(address(this).balance);
        } else {
            returnData = target.directCall(data);
        }
    }

    /**
     * @dev Calls a component and returns the result. This function is used to delegate call to the fee bank.
     * Only callable by a verified component operator.
     * @param component The component address.
     * @param data The data to call the component with.
     * @return The result of the call.
     */
    function _callComponent(address component, bytes calldata data)
        internal
        onlyVerifiedComponentOperator(component)
        returns (bytes memory)
    {
        return _FEE_BANK.delegateCall(component, data);
    }
}

