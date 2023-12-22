// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IAccessControlUpgradeable.sol";

interface IReferrals is IAccessControlUpgradeable {
    function setReferralForEthAddress(bytes32 code, address ethAccount)
        external;

    function setReferralForTradeAccount(bytes32 code, uint256 tradeAccountId)
        external;
}

