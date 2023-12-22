pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

/**
 * @title Interface for different royalty schemes.
 * @author Nevermined
 */
interface IRoyaltyScheme {
    /**
     * @notice check that royalties are correct
     * @param _did compute royalties for this DID
     * @param _amounts amounts in payment
     * @param _receivers receivers of payments
     * @param _tokenAddress payment token. zero address means native token (ether)
     */
    function check(bytes32 _did,
        uint256[] memory _amounts,
        address[] memory _receivers,
        address _tokenAddress) external view returns (bool);
}

