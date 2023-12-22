// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {ISafeOwnable} from "./ISafeOwnable.sol";

import {IFeeBank} from "./IFeeBank.sol";

interface IFeeManager is ISafeOwnable {
    error FeeManager__ComponentNotVerified();
    error FeeManager__OnlyComponentOperator();
    error FeeManager__ComponentAlreadyVerified();
    error FeeManager__ComponentOperatorAlreadyAdded();
    error FeeManager__ComponentOperatorNotAdded();
    error FeeManager__FeeBankIsNotAComponent();
    error FeeManager__InvalidLength();

    struct Component {
        mapping(address => uint256) operators;
        uint256 verifiedRound;
    }

    event ComponentVerified(address indexed component, uint256 indexed round);

    event ComponentUnverified(address indexed component);

    event ComponentOperatorAdded(address indexed component, address indexed operator, uint256 indexed round);

    event ComponentOperatorRemoved(address indexed component, address indexed operator);

    function getFeeBank() external view returns (IFeeBank);

    function isVerifiedComponent(address component) external view returns (bool);

    function isComponentOperator(address component, address operator) external view returns (bool);

    function batchStaticCall(address[] calldata targets, bytes[] calldata data)
        external
        view
        returns (bytes[] memory results);

    function verifyComponent(address component) external;

    function unverifyComponent(address component) external;

    function addComponentOperator(address component, address operator) external;

    function removeComponentOperator(address component, address operator) external;

    function callComponent(address component, bytes calldata data) external returns (bytes memory);

    function callComponents(address[] calldata component, bytes[] calldata data) external returns (bytes[] memory);

    function directCall(address target, bytes calldata data) external returns (bytes memory);
}

