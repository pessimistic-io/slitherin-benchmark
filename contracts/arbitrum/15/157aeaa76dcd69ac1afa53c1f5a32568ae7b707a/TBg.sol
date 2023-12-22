// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasuryToken.sol";

/**
 * @title Treasury Bond Gold Token
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 * 
 * To know more about the ecosystem you can find us on https://satoshilira.io don't trust, verify!
 */
contract TBg is TreasuryToken {
    constructor(address token_, uint rate_) TreasuryToken('Treasury Bond Gold', 'TBg', token_, rate_) {}
}

