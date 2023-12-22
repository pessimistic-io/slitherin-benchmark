pragma solidity 0.8.14;

import "./IDatabase.sol";

/// @title   Audit Inherit
/// @notice  Contract that audited contracts will inherit form
/// @author  Hyacinth
abstract contract AuditInherit {
    /// MODIFIERS ///

    modifier auditPassed() {
        _auditedPassed();
        _;
    }

    /// ERRORS ///

    /// @notice Error for if the audit has not passed
    error AuditNotPassed();

    /// STATE VARIABLES ///

    /// @notice Address of database
    address public immutable database;

    /// CONSTRUCTOR ///

    /// @param database_  Address of databse
    constructor(address database_, address previous_) {
        database = database_;
        IDatabase(database_).beingAudited(previous_);
    }
    
    /// INTERNAL VIEW FUNCTION ///

    function _auditedPassed() internal view {
        (, , IDatabase.STATUS status_, , ) = IDatabase(database).audits(address(this));
        if (status_ != IDatabase.STATUS.PASSED) revert AuditNotPassed();
    }
}

