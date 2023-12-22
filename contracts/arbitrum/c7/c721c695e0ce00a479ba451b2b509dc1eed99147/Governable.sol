//    SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Context.sol";
import "./Ownable.sol";

abstract contract Governable is Context {
    address private _governance;

    event GovernanceChanged(address indexed formerGov, address indexed newGov);

    /**
     * @dev Throws if called by any account other than the governance.
     */
    modifier onlyGovernance() {
        require(governance() == _msgSender(), "DZG001");
        _;
    }

    /**
     * @dev Initializes the contract setting the deployer as the initial governance.
     */
    constructor(address governance_) {
        require(governance_ != address(0), "DZG002");
        _governance = governance_;
        emit GovernanceChanged(address(0), governance_);
    }

    /**
     * @dev Returns the address of the current governance.
     */
    function governance() public view virtual returns (address) {
        return _governance;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newGov_`).
     * Can only be called by the current governance.
     */
    function changeGovernance(address newGov_) public virtual onlyGovernance {
        require(newGov_ != address(0), "DZG002");
        emit GovernanceChanged(_governance, newGov_);
        _governance = newGov_;
    }
}
