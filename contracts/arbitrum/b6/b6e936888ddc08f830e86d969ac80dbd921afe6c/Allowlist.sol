// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Ownable } from "./Ownable.sol";

import { IAllowlist } from "./IAllowlist.sol";

/* 
The Allowlist contract is primarily used to set up a list of whitelisted users. 
The CreditCaller contract will bind to this contract address, 
and when a user applies for a loan, it will check whether the user is on the whitelist.
*/

contract Allowlist is Ownable, IAllowlist {
    bool public passed;

    address[] public plugins;

    mapping(address => bool) public accounts;
    mapping(address => bool) private governors;

    event Permit(address[] indexed _account, uint256 _timestamp);
    event Forbid(address[] indexed _account, uint256 _timestamp);
    event TogglePassed(bool _currentState, uint256 _timestamp);
    event NewGovernor(address _newGovernor);
    event AddPlugin(address _plugin);

    modifier onlyGovernors() {
        require(isGovernor(msg.sender), "Allowlist: Caller is not governor");
        _;
    }

    /// @notice used to initialize the contract
    constructor(bool _passed) {
        passed = _passed;
    }

    /// @notice add plugin
    /// @param _plugin plugin address
    function addPlugin(address _plugin) public onlyOwner {
        require(_plugin != address(0), "Allowlist: _plugin cannot be 0x0");

        for (uint256 i = 0; i < plugins.length; i++) {
            require(plugins[i] != _plugin, "Allowlist: Duplicate _plugin");
        }

        plugins.push(_plugin);

        emit AddPlugin(_plugin);
    }

    /// @notice remove plugin
    /// @param _index plugin index
    function removePlugin(uint256 _index) public onlyOwner {
        require(_index < plugins.length, "Allowlist: Index out of range");

        plugins[_index] = plugins[plugins.length - 1];
        plugins.pop();
    }

    /// @notice judge if its governor
    /// @param _governor owner address
    /// @return bool value
    function isGovernor(address _governor) public view returns (bool) {
        return governors[_governor];
    }

    /// @notice add governor
    /// @param _newGovernor governor address
    function addGovernor(address _newGovernor) public onlyOwner {
        require(_newGovernor != address(0), "Allowlist: _newGovernor cannot be 0x0");
        require(!isGovernor(_newGovernor), "Allowlist: _newGovernor is already governor");

        governors[_newGovernor] = true;

        emit NewGovernor(_newGovernor);
    }

    // @notice permit account
    /// @param _accounts user array
    function permit(address[] calldata _accounts) public onlyGovernors {
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i] != address(0), "Allowlist: Account cannot be 0x0");

            accounts[_accounts[i]] = true;
        }

        emit Permit(_accounts, block.timestamp);
    }

    /// @notice forbid account
    /// @param _accounts user array
    function forbid(address[] calldata _accounts) public onlyGovernors {
        for (uint256 i = 0; i < _accounts.length; i++) {
            accounts[_accounts[i]] = false;
        }

        emit Forbid(_accounts, block.timestamp);
    }

    /// @notice toggle allow list
    function togglePassed() public onlyGovernors {
        passed = !passed;

        emit TogglePassed(passed, block.timestamp);
    }

    /// @notice check account
    /// @param _account user address
    /// @return boolean
    function can(address _account) external view override returns (bool) {
        if (passed) return true;

        for (uint256 i = 0; i < plugins.length; i++) {
            if (IAllowlist(plugins[i]).can(_account)) return true;
        }

        return accounts[_account];
    }

    function pluginsLength() public view returns (uint256) {
        return plugins.length;
    }

    /// @dev Rewriting methods to prevent accidental operations by the owner.
    function renounceOwnership() public virtual override onlyOwner {
        revert("Allowlist: Not allowed");
    }
}

