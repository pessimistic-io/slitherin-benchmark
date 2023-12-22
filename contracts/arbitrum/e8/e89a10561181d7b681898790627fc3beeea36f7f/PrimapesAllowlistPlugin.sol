// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC721 } from "./IERC721.sol";
import { IAllowlistPlugin } from "./IAllowlistPlugin.sol";

contract PrimapesAllowlistPlugin is IAllowlistPlugin {
    address public constant PRIMAPES_ADDRESS = 0x72C3205ACF3eB2B37B0082240bF0B909a46C0993;

    function can(address _account) external view override returns (bool) {
        return IERC721(PRIMAPES_ADDRESS).balanceOf(_account) > 0 ? true : false;
    }
}

