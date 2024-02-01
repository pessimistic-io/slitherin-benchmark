// SPDX-License-Identifier: BUSDL-1.1
pragma solidity 0.6.11;

import {Address} from "./libraries_Imports.sol";
import {PoolToken} from "./PoolToken.sol";
import {UpgradeableContractFactory} from "./UpgradeableContractFactory.sol";

contract PoolTokenV1Factory is UpgradeableContractFactory {
    using Address for address;

    address private _logic;

    function _deployLogic(bytes memory initData)
        internal
        virtual
        override
        returns (address)
    {
        if (_logic != address(0)) {
            return _logic;
        }
        PoolToken logic = new PoolToken();
        _logic = address(logic);
        _logic.functionCall(initData);
        return _logic;
    }
}

