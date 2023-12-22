// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Camelotinterface.sol";
import "./ERC20.sol";

contract Test is ERC20 {
    ICamelotRouter public camelotRouter =
        ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

    constructor() ERC20("test", "test") {}

    function create() public {
        address factory = camelotRouter.factory();
        ICamelotFactory(factory).createPair(
            camelotRouter.WETH(),
            address(this)
        );
    }
}

