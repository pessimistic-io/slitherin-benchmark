// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IACLManager {
    function addEmergencyAdmin(address _admin) external;

    function isEmergencyAdmin(address _admin) external view returns (bool);

    function removeEmergencyAdmin(address _admin) external;

    function addGovernance(address _governance) external;

    function isGovernance(address _governance) external view returns (bool);

    function removeGovernance(address _governance) external;

    function addOperator(address _operator) external;

    function isOperator(address _operator) external view returns (bool);

    function removeOperator(address _operator) external;

    function addBidsContract(address _bids) external;

    function isBidsContract(address _bids) external view returns (bool);

    function removeBidsContract(address _bids) external;
}

