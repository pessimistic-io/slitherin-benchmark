// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

interface IOracleEvents {
    event SetMuonAppId(uint256 oldId, uint256 newId);
    event SetMuonAppCID(bytes oldCID, bytes newCID);
    event SetMuonPublicKey(uint256 oldX, uint8 oldParity, uint256 newX, uint8 newParity);
    event SetMuonGatewaySigner(address oldSigner, address newSigner);
}

