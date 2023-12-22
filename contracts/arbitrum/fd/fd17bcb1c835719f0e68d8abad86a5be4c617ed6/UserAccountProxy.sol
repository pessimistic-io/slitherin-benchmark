// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Proxy } from "./Proxy.sol";
import { IUserAccountImpl } from "./IUserAccountImpl.sol";

/**
 * @title InitializedProxy
 * @author 0xkongamoto
 */
contract UserAccountProxy is Proxy {
    //
    IUserAccountImpl internal immutable _userAccountImpl;

    // ======== Constructor =========
    constructor(IUserAccountImpl userAccountImplArg) {
        _userAccountImpl = userAccountImplArg;
    }

    /**
     * @dev This is a virtual function that should be overridden so it returns the address to which the fallback function
     * and {_fallback} should delegate.
     */
    function _implementation() internal view virtual override returns (address impl) {
        return _userAccountImpl.getUserAccountImpl();
    }
}

