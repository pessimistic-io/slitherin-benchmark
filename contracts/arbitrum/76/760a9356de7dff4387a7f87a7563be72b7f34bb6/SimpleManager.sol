// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IManager} from "./Borrower.sol";

contract SimpleManager is IManager {
    function callback(bytes calldata data) external override returns (uint144) {
        (bool success, ) = msg.sender.call(data);
        require(success);
        return 0;
    }
}

