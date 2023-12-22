// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

/// @title MasterChefLib
library MasterChefLib {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}

