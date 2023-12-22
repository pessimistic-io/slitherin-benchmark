// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./Ownable.sol";

contract TroveStreetPunksReward is Ownable {

    uint256 public totalSupply;

    mapping(address => bool) private operators;

    mapping(address => uint256) private balances;

    mapping(address => mapping(address => uint256)) private allowances;

    constructor() { }

    function addOperator(address _address) external onlyOwner {
        require(_address != address(0), "Operator as zero address");
        operators[_address] = true;
    }

    function removeOperator(address _address) external onlyOwner {
        delete operators[_address];
    }

    function mint(address _account, uint256 _amount) external {
        require(operator(_msgSender()), "Caller is not the operator");
        require(_account != address(0), "Mint to the zero address");

        totalSupply += _amount;
        balances[_account] += _amount;
    }

    function burn(uint256 _amount) public returns (bool) {
        address owner = _msgSender();
        _burn(owner, _amount);
        return true;
    }

    function burnFrom(
        address _from,
        uint256 _amount
    ) public returns (bool) {
        address spender = _msgSender();
        _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return true;
    }

    function approve(address _spender, uint256 _amount) public returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, _amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, allowance(owner, _spender) + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, _spender);
        require(currentAllowance >= _subtractedValue, "Decreased allowance below zero");
        unchecked {
            _approve(owner, _spender, currentAllowance - _subtractedValue);
        }

        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function balanceOf(address _account) public view returns (uint256) {
        return balances[_account];
    }

    function operator(address _address) public view returns (bool) {
        return operators[_address];
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        require(_owner != address(0), "Approve from the zero address");
        require(_spender != address(0), "Approve to the zero address");

        allowances[_owner][_spender] = _amount;
    }

    function _spendAllowance(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        uint256 currentAllowance = allowance(_owner, _spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= _amount, "Insufficient allowance");
            unchecked {
                _approve(_owner, _spender, currentAllowance - _amount);
            }
        }
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "Burn from the zero address");

        uint256 accountBalance = balances[_account];
        require(accountBalance >= _amount, "Burn amount exceeds balance");
        unchecked {
            balances[_account] = accountBalance - _amount;
        }

        totalSupply -= _amount;
    }

}
