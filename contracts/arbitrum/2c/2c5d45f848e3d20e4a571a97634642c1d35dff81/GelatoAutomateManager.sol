// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { AccessControl } from "./AccessControl.sol";
import { Multicall } from "./Multicall.sol";

interface ICreditRewardTracker {
    function setPendingOwner(address _owner) external;

    function acceptOwner() external;

    function harvestDepositors() external;

    function harvestManagers() external;
}

contract GelatoAutomateManager is AccessControl {
    bytes32 public constant GELATO_ROLE = keccak256("GELATO_ROLE");

    address public creditRewardTracker;
    uint256 public lastExecuted;

    event Succeed(address _sender, uint256 _timestamp);
    event Failed(address _sender, uint256 _timestamp);

    constructor(address _owner, address _creditRewardTracker) {
        require(_owner != address(0), "GelatoAutomateManager: _owner cannot be 0x0");
        require(_creditRewardTracker != address(0), "GelatoAutomateManager: _creditRewardTracker cannot be 0x0");

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(GELATO_ROLE, _owner);

        creditRewardTracker = _creditRewardTracker;
    }

    function harvest() public onlyRole(GELATO_ROLE) {
        require(block.timestamp - lastExecuted > 12 hours, "GelatoAutomateManager: Execution interval is too frequent");

        try ICreditRewardTracker(creditRewardTracker).harvestDepositors() {
            emit Succeed(msg.sender, lastExecuted);
        } catch {
            emit Failed(msg.sender, lastExecuted);
        }

        try ICreditRewardTracker(creditRewardTracker).harvestManagers() {
            emit Succeed(msg.sender, lastExecuted);
        } catch {
            emit Failed(msg.sender, lastExecuted);
        }

        lastExecuted = block.timestamp;
    }

    function revertOwner(address _target) public onlyRole(DEFAULT_ADMIN_ROLE) {
        ICreditRewardTracker(creditRewardTracker).setPendingOwner(_target);
        ICreditRewardTracker(creditRewardTracker).acceptOwner();
    }
}

