// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MuonClientBase.sol";

contract MuonClient is Initializable, MuonClientBase {
    function __MuonClient_init(
        uint256 _muonAppId,
        PublicKey memory _muonPublicKey
    ) public onlyInitializing {
        validatePubKey(_muonPublicKey.x);

        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
    }
}

