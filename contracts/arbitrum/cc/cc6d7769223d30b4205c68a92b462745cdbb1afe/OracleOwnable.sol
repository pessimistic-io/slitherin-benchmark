// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { OracleInternal } from "./OracleInternal.sol";
import { PublicKey, SchnorrSign } from "./OracleStorage.sol";
import { IOracleEvents } from "./IOracleEvents.sol";

contract OracleOwnable is AccessControlInternal, IOracleEvents {
    function setMuonAppId(uint256 muonAppId) external onlyRole(ADMIN_ROLE) {
        emit SetMuonAppId(OracleInternal.getMuonAppId(), muonAppId);
        OracleInternal.setMuonAppId(muonAppId);
    }

    function setMuonAppCID(bytes calldata muonAppCID) external onlyRole(ADMIN_ROLE) {
        emit SetMuonAppCID(OracleInternal.getMuonAppCID(), muonAppCID);
        OracleInternal.setMuonAppCID(muonAppCID);
    }

    function setMuonPublicKey(uint256 x, uint8 parity) external onlyRole(ADMIN_ROLE) {
        PublicKey memory oldKey = OracleInternal.getMuonPublicKey();
        emit SetMuonPublicKey(oldKey.x, oldKey.parity, x, parity);
        OracleInternal.setMuonPublicKey(PublicKey(x, parity));
    }

    function setMuonGatewaySigner(address muonGatewaySigner) external onlyRole(ADMIN_ROLE) {
        emit SetMuonGatewaySigner(OracleInternal.getMuonGatewaySigner(), muonGatewaySigner);
        OracleInternal.setMuonGatewaySigner(muonGatewaySigner);
    }
}

