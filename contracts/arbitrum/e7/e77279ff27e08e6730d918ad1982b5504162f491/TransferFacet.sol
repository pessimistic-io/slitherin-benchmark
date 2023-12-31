// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import {BFacetOwner} from "./BFacetOwner.sol";
import {Address} from "./Address.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {NATIVE_TOKEN} from "./CTokens.sol";

contract TransferFacet is BFacetOwner {
    using Address for address payable;
    using SafeERC20 for IERC20;

    function transfer(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyOwner {
        if (_token == NATIVE_TOKEN) payable(_recipient).sendValue(_amount);
        else IERC20(_token).safeTransfer(_recipient, _amount);
    }
}

