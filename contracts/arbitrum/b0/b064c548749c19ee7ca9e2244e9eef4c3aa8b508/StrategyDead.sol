// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Strategy} from "./Strategy.sol";
import {IERC20} from "./IERC20.sol";

contract StrategyDead is Strategy {
    string public name = "Dead";

    constructor(address _strategyHelper) Strategy(_strategyHelper) {}

    function _rate(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _mint(address ast, uint256 amt, bytes calldata) internal view override returns (uint256) {
      // Do not revert on small amount to allow repaying borrow and closing
      if (strategyHelper.value(ast, amt) < 2.5e18) {
          return 0;
      }
      revert("Dead strategy");
    }

    function _burn(address, uint256, bytes calldata) internal pure override returns (uint256) {
        // Do not revert so positions can still be closed down 
        return 0;
    }

    function rescueToken(address token, uint256 amount) external auth {
        IERC20(token).transfer(msg.sender, amount);
    }
}

