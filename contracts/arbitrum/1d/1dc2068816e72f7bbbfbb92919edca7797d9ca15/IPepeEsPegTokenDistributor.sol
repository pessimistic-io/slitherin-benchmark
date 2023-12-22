//SPDX-License-Identifier: ISC

pragma solidity 0.8.19;

interface IPepeEsPegTokenDistributor {
    function setRecipients(address[] calldata _recipients, uint256[] calldata _claimableAmount) external;

    function enableClaim() external;

    function disableClaim() external;

    function claim() external;

    function getClaimableAmount(address _user) external view returns (uint256);

    function getTotalClaimable() external view returns (uint256);
}

