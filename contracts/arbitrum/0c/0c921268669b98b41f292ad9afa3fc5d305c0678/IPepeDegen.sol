//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeDegen {
    function setRecipients(address[] calldata _users, uint256[] calldata _claimableAmount) external;

    function claim(uint32 epochId) external;

    function claimAll() external;

    function enableClaim(uint32 epochId) external;

    function disableClaim(uint32 epochId) external;

    function totalClaimable(address user) external view returns (uint256);

    function retrieve(address _token) external;
}

