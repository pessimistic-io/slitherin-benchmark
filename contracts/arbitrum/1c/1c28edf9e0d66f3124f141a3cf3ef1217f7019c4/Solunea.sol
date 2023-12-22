// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";

contract Solunea is IERC20 {
    string public constant symbol = "SLNA";
    string public constant name = "Solunea";
    uint8 public constant decimals = 18;
    uint256 public override totalSupply = 0;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public minter;

    constructor() {
        minter = msg.sender;
        _mint(msg.sender, 24000000000000000000000000); //24M tokens for initial liquidity
    }

    // No checks as its meant to be once off to set minting rights to Minter
    function setMinter(address _minter) external {
        require(msg.sender == minter, "Solunea: Not minter");
        minter = _minter;
    }

    function approve(address _spender, uint256 _value) external override returns (bool) {
        require(_spender != address(0), "Solunea: Approve to the zero address");
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function _mint(address _to, uint256 _amount) internal returns (bool) {
        require(_to != address(0), "Solunea: Mint to the zero address");
        balanceOf[_to] += _amount;
        totalSupply += _amount;
        emit Transfer(address(0x0), _to, _amount);
        return true;
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal returns (bool) {
        require(_to != address(0), "Solunea: Transfer to the zero address");

        uint256 fromBalance = balanceOf[_from];
        require(fromBalance >= _value, "Solunea: Transfer amount exceeds balance");
        unchecked {
            balanceOf[_from] = fromBalance - _value;
        }

        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    function transfer(address _to, uint256 _value) external override returns (bool) {
        return _transfer(msg.sender, _to, _value);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external override returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowance[_from][spender];
        if (spenderAllowance != type(uint256).max) {
            require(spenderAllowance >= _value, "Solunea: Insufficient allowance");
            unchecked {
                uint256 newAllowance = spenderAllowance - _value;
                allowance[_from][spender] = newAllowance;
                emit Approval(_from, spender, newAllowance);
            }
        }
        return _transfer(_from, _to, _value);
    }

    function mint(address account, uint256 amount) external returns (bool) {
        require(msg.sender == minter, "Solunea: Not minter");
        _mint(account, amount);
        return true;
    }
}

