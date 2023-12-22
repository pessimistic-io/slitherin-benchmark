// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { IERC721 } from "./IERC721.sol";
import { IAllowlistPlugin } from "./IAllowlistPlugin.sol";

interface IBlacklisted {
    function isBlacklisted(address _address) external view returns (bool);
}

contract GBCAllowlistPlugin is IAllowlistPlugin {
    address public constant GBC_ADDRESS = 0x17f4BAa9D35Ee54fFbCb2608e20786473c7aa49f;

    function can(address _account) external view override returns (bool) {
        if (IBlacklisted(GBC_ADDRESS).isBlacklisted(_account)) return false;
        return IERC721(GBC_ADDRESS).balanceOf(_account) > 0 ? true : false;
    }
}

