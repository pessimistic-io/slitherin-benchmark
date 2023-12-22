// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRefundController {
    function totalRefundedAmount(address _tokenAddress) external view returns (uint256);

    function openRefundWindow(
        uint256 _claimableAt,
        address _tokenAddress,
        address[] memory _fundingPools
    ) external;

    function eligibleForRefund(address _userAllocation, address _tokenAddress) external view returns (uint256);

    function updateUserEligibility(address _userAllocation, address _tokenAddress, uint256 _eligibility) external; 

    function windowCloseUntil(address _tokenAddress) external view returns (uint256);

    function grantRole(bytes32 role, address account) external;
}

