// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRoyaltyRegistry {
    function addRegistrant(address registrant) external;

    function removeRegistrant(address registrant) external;

    function setRoyalty(address _erc721address, address payable _payoutAddress, uint256 _payoutPerMille) external;

    function getRoyaltyPayoutAddress(address _erc721address) external view returns (address payable);

    function getRoyaltyPayoutRate(address _erc721address) external view returns (uint256);
}
