// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Initializable } from "./Initializable.sol";
import { BaseRelayRecipient } from "./BaseRelayRecipient.sol";

contract TestMetaTxRecipient is BaseRelayRecipient, Initializable {
    address public pokedBy;

    function __TestMetaTxRecipient_init(address trustedForwarderArg) external initializer {
        _setTrustedForwarder(trustedForwarderArg);
    }

    function poke() external {
        pokedBy = _msgSender();
    }

    // solhint-disable
    function error() external pure {
        revert("MetaTxRecipientMock: Error");
    }
}

