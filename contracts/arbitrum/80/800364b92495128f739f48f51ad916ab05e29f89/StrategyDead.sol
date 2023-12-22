// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategyHelper} from "./IStrategyHelper.sol";

contract StrategyDead is Util {
    string public name = "Dead";

    uint256 public cap;
    uint256 public totalShares;
    uint256 public status = 4;
    IStrategyHelper public strategyHelper;

    event File(bytes32 indexed what, address data);

    constructor(address _strategyHelper) {
        exec[msg.sender] = true;
        strategyHelper = IStrategyHelper(_strategyHelper);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "exec") exec[data] = !exec[data];
        emit File(what, data);
    }

    function rate(uint256) public pure returns (uint256) {
        return 0;
    }

    function mint(address ast, uint256 amt, bytes calldata) external view returns (uint256) {
        // Do not revert on small amount to allow repaying borrow and closing
        if (strategyHelper.value(ast, amt) < 2.5e18) {
            return 0;
        }
        revert("Dead strategy");
    }

    function burn(address, uint256, bytes calldata) external pure returns (uint256) {
        // Do not revert so positions can still be closed down 
        return 0;
    }

    function earn() public { }

    function exit(address) public { }

    function move(address) public { }

    function rescueToken(address token, uint256 amount) external auth {
        IERC20(token).transfer(msg.sender, amount);
    }
}

