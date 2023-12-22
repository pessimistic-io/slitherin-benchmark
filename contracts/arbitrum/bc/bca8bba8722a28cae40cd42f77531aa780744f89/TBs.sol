// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TreasuryToken.sol";

/**
 * @title Treasury Bond Silver Token
 * @author Satoshi LIRA Team
 * @custom:security-contact contact@satoshilira.io
 * 
 * To know more about the ecosystem you can find us on https://satoshilira.io don't trust, verify!
 */
contract TBs is TreasuryToken {
    constructor(address token_, uint rate_) TreasuryToken('Treasury Bond Silver', 'TBs', token_, rate_) {}
}

