// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./DataTypes.sol";

interface IServiceAgreement {
    function updateServiceAgreement(DataTypes.SAParams calldata _newAgreement) external;
    function agreementParams() external view returns (DataTypes.SAParams memory);
    function stakedToken() external view returns (address);
    function stakedAmount() external view returns (uint256);
    function disputeStake() external view returns (uint256);
    function slashAmount() external view returns (uint256);
}
