//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./IToadzOneOfOneExchange.sol";
import "./IToadz.sol";
import "./AdminableUpgradeable.sol";

abstract contract ToadzOneOfOneExchangeState is Initializable, IToadzOneOfOneExchange, AdminableUpgradeable {

    IToadz public toadz;

    EnumerableSetUpgradeable.AddressSet internal oneOfOneRecipients;

    mapping(address => ToadTraits) public recipientToTraits;
    mapping(address => bool) public recipientToHasClaimed;

    function __ToadzOneOfOneExchangeState_init() internal initializer {
        AdminableUpgradeable.__Adminable_init();
    }
}
