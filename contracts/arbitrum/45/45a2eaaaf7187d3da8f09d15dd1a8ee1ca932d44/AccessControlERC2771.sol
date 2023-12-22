// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import { Context } from "./Context.sol";

import { ERC2771ContextInternal } from "./ERC2771ContextInternal.sol";
import { AccessControlInternal } from "./AccessControlInternal.sol";

abstract contract AccessControlERC2771 is ERC2771ContextInternal, AccessControlInternal {
    function _msgSender() internal view virtual override(Context, ERC2771ContextInternal) returns (address) {
        return ERC2771ContextInternal._msgSender();
    }

    function _msgData() internal view virtual override(Context, ERC2771ContextInternal) returns (bytes calldata) {
        return ERC2771ContextInternal._msgData();
    }
}

