// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Address } from "./Address.sol";

import { ICreditManager } from "./ICreditManager.sol";
import { IDepositor } from "./IDepositor.sol";

contract CreditRewardTracker {
    using Address for address;

    address public owner;
    address public pendingOwner;
    uint256 public lastInteractedAt;
    uint256 public duration;

    address[] public managers;
    address[] public depositors;

    mapping(address => bool) private governors;

    error NotAuthorized();
    event NewGovernor(address indexed _sender, address _governor);
    event RemoveGovernor(address indexed _sender, address _governor);
    event Succeed(address _sender, address _target, uint256 _claimed, uint256 _timestamp);
    event Failed(address _sender, address _target, uint256 _timestamp);

    modifier onlyOwner() {
        if (owner != msg.sender) revert NotAuthorized();
        _;
    }

    modifier onlyGovernors() {
        if (!isGovernor(msg.sender)) revert NotAuthorized();
        _;
    }

    constructor(address _owner) {
        require(_owner != address(0), "CreditRewardTracker: _distributer cannot be 0x0");

        owner = _owner;

        governors[_owner] = true;
        duration = 10 minutes;
    }

    /// @notice Set pending owner
    /// @param _owner owner address
    function setPendingOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "CreditRewardTracker: _owner cannot be 0x0");
        pendingOwner = _owner;
    }

    /// @notice Accept owner
    function acceptOwner() external onlyOwner {
        owner = pendingOwner;

        pendingOwner = address(0);
    }

    /// @notice Add new governor
    /// @param _newGovernor governor address
    function addGovernor(address _newGovernor) public onlyOwner {
        require(_newGovernor != address(0), "CreditRewardTracker: _newGovernor cannot be 0x0");
        require(!isGovernor(_newGovernor), "CreditRewardTracker: _newGovernor is already governor");

        governors[_newGovernor] = true;

        emit NewGovernor(msg.sender, _newGovernor);
    }

    function addGovernors(address[] calldata _newGovernors) external onlyOwner {
        for (uint256 i = 0; i < _newGovernors.length; i++) {
            addGovernor(_newGovernors[i]);
        }
    }

    /// @notice Remove governor
    /// @param _governor governor address
    function removeGovernor(address _governor) external onlyOwner {
        require(_governor != address(0), "CreditRewardTracker: _governor cannot be 0x0");
        require(isGovernor(_governor), "CreditRewardTracker: _governor is not a governor");

        governors[_governor] = false;

        emit RemoveGovernor(msg.sender, _governor);
    }

    function isGovernor(address _governor) public view returns (bool) {
        return governors[_governor];
    }

    function addManager(address _manager) public onlyOwner {
        require(_manager != address(0), "CreditRewardTracker: _manager cannot be 0x0");

        for (uint256 i = 0; i < managers.length; i++) {
            require(managers[i] != _manager, "CreditRewardTracker: Duplicate manager");
        }

        managers.push(_manager);
    }

    function removeManager(uint256 _index) public onlyOwner {
        require(_index < managers.length, "CreditRewardTracker: Index out of range");

        managers[_index] = managers[managers.length - 1];

        managers.pop();
    }

    function addDepositor(address _depositor) public onlyOwner {
        require(_depositor != address(0), "CreditRewardTracker: _depositor cannot be 0x0");

        for (uint256 i = 0; i < depositors.length; i++) {
            require(depositors[i] != _depositor, "CreditRewardTracker: Duplicate depositor");
        }

        depositors.push(_depositor);
    }

    function removeDepositor(uint256 _index) public onlyOwner {
        require(_index < depositors.length, "CreditRewardTracker: Index out of range");

        depositors[_index] = depositors[depositors.length - 1];

        depositors.pop();
    }

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function execute() external onlyGovernors {
        require(block.timestamp - lastInteractedAt >= duration, "CreditRewardTracker: Incorrect duration");

        lastInteractedAt = block.timestamp;

        for (uint256 i = 0; i < depositors.length; i++) {
            try IDepositor(depositors[i]).harvest() returns (uint256 claimed) {
                emit Succeed(msg.sender, depositors[i], claimed, lastInteractedAt);
            } catch {
                emit Failed(msg.sender, managers[i], lastInteractedAt);
            }
        }

        for (uint256 i = 0; i < managers.length; i++) {
            try ICreditManager(managers[i]).harvest() returns (uint256 claimed) {
                emit Succeed(msg.sender, managers[i], claimed, lastInteractedAt);
            } catch {
                emit Failed(msg.sender, managers[i], lastInteractedAt);
            }
        }
    }
}

