//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPepeReferral {
    function addReferrers(address[] calldata referrers, uint256[] calldata allocations) external;

    function claimUsdc(uint256 epochId) external;

    function claimAll() external;

    function retrieve(address _token) external;

    function getReferrers(uint256 epochId) external view returns (address[] memory);

    function getAllocations(uint256 epochId) external view returns (uint256[] memory);

    function getReferrerIndex(uint256 epochId, address referrer) external view returns (uint256);

    function getClaimableUsdc(address referrer) external view returns (uint256);

    function getClaimableUsdc(uint256 epochId, address referrer) external view returns (uint256);

    function getUnclaimedAllocation(uint256 epochId) external view returns (uint256);

    function isClaimEnabled(uint256 epochId) external view returns (bool);

    function enableClaim(uint256 epochId) external;

    function disableClaim(uint256 epochId) external;
}

