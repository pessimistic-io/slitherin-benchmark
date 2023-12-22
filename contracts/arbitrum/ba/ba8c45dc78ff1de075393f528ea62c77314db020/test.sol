// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./Camelotinterface.sol";


contract Test { 
       ICamelotRouter public camelotRouter = ICamelotRouter(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);

      function create() public  {
          address factory = camelotRouter.factory();
          ICamelotFactory(factory).createPair(address(this), camelotRouter.WETH());
       }
}
