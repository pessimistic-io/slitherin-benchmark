// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMutant {
    function addToAllowList(address[] calldata addresses) external;

    function onAllowList(address addr) external returns (bool);

    function removeFromAllowList(address[] calldata addresses) external;

    function allowListClaimedBy(address owner) external returns (uint256);

    function allowedForClaim(address owner) external returns (uint256);

    function claim(uint256 numberOfTokens) external;

    function purchase(uint256 numberOfTokens) external payable;

    function purchaseAllowList(uint256 numberOfTokens) external payable;

    function gift(address[] calldata to) external;

    function setClaimingIsActive(bool _isActiveClaiming) external;

    function setIsActive(bool _isActive) external;

    function setIsAllowListActive(bool _isAllowListActive) external;

    function setAllowListMaxMint(uint256 maxMint) external;

    function setProof(string memory proofString) external;

    function withdraw() external;
}
