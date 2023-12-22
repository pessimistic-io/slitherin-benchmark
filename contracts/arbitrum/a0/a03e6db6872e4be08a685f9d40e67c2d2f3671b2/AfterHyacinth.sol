pragma solidity 0.8.14;

import "./SafeERC20.sol";

// 1. Import AuditInherit contract
import "./AuditInherit.sol";

// 2. Inherit from AuditInherit contract
contract AfterHyacinth is AuditInherit {
    using SafeERC20 for IERC20;

    // 3. Pass in Hyacinth database address and previous contract if rollover
    constructor(address database_, address previous_) AuditInherit(database_, previous_) {}

    // 4. Use modifier auditPassed in functions
    function transferIn(address token_, uint256 amount_) auditPassed external {
        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);
    }

    function transferOut(address token_, uint256 amount_) auditPassed external {
        IERC20(token_).safeTransfer(msg.sender, amount_);
    }
}

