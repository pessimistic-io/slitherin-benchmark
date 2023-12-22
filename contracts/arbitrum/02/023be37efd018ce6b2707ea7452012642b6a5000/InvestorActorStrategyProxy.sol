// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategy} from "./IStrategy.sol";

contract InvestorActorStrategyProxy is Util {
    event File(bytes32 indexed what, address data);

    constructor() {
        exec[msg.sender] = true;
    }

    function file(bytes32 what, address data) public auth {
        if (what == "exec") exec[data] = !exec[data];
        emit File(what, data);
    }

    function mint(address str, address ast, uint256 amt, bytes calldata dat) public auth returns (uint256) {
        IERC20(ast).approve(str, amt);
        return IStrategy(str).mint(ast, amt, dat);
    }

    function burn(address str, address ast, uint256 sha, bytes calldata dat) public auth returns (uint256) {
        uint256 amt = IStrategy(str).burn(ast, sha, dat);
        IERC20(ast).transfer(msg.sender, amt);
        return amt;
    }
}

