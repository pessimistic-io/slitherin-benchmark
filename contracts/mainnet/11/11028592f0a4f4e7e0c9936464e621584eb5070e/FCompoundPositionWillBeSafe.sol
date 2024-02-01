// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import {DAI} from "./CTokens.sol";
import {     _getCToken,     _wouldCompoundAccountBeLiquid } from "./FCompound.sol";

function _compoundPositionWillBeSafe(
    address _dsa,
    address _colToken,
    uint256 _colAmt,
    address _debtToken,
    uint256 _debtAmt
) view returns (bool) {
    return
        _wouldCompoundAccountBeLiquid(
            _dsa,
            _getCToken(_colToken),
            _colAmt,
            _getCToken(_debtToken),
            _debtAmt
        );
}

