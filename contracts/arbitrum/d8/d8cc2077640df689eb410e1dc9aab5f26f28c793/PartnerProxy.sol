// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Util} from "./Util.sol";
import {IERC20} from "./IERC20.sol";

contract PartnerProxy is Util {
    error CallReverted();

    constructor() {
        exec[msg.sender] = true;
    }

    receive() external payable {}

    function setExec(address usr, bool can) public auth {
        exec[usr] = can;
    }

    function call(address tar, uint256 val, bytes calldata dat) public payable auth returns (bytes memory) {
        (bool suc, bytes memory res) = tar.call{value: val}(dat);
        if (!suc) revert CallReverted();
        return res;
    }

    function pull(address tkn) public auth {
        IERC20(tkn).transfer(msg.sender, IERC20(tkn).balanceOf(address(this)));
    }

    function approve(address tkn, address tar) public auth {
        IERC20(tkn).approve(tar, IERC20(tkn).balanceOf(address(this)));
    }
}

