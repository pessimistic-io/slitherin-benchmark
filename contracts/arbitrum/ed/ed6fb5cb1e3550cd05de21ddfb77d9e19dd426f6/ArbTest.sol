// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ICamelotFactory.sol";
import "./ICamelotRouter.sol";
import "./ERC20.sol";

contract ArbTest is
ERC20 {
    ICamelotRouter public immutable router;
    address public immutable factory;
    address public immutable weth;
    address public pair;

    constructor(
        address routerAddress_
    ) ERC20('ArbTest', 'ArbTest') {
        //        address routerAddress_ = '0xc873fEcbd354f5A56E00E710B90EF4201db2448d';
        router = ICamelotRouter(routerAddress_);
        factory = router.factory();
        weth = router.WETH();
//        pair = ICamelotFactory(factory).createPair(address(this), weth);

        _mint(_msgSender(), 10000 * 10 ** 18);
    }
}

