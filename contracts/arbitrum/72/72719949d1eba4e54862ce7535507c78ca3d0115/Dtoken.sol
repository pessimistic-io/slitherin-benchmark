// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IERC20Upgradeable.sol";
import "./Initializable.sol";

// import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Dtoken is IERC20Upgradeable, Initializable /* , UUPSUpgradeable, OwnableUpgradeable */ {
    string public constant symbol = "DTOKEN";
    string public constant name = "Dtoken";
    uint8 public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    address public minter;

    // constructor() {
    //     minter = msg.sender;
    //     _mint(msg.sender, 0);
    // }

    function initialize() public initializer {
        // __Ownable_init_unchained();
        minter = msg.sender;
        _mint(msg.sender, 0);
    }

    // function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // No checks as its meant to be once off to set minting rights to Minter
    function setMinter(address _minter) external {
        require(msg.sender == minter, "Dtoken: Not minter");
        minter = _minter;
    }

    function approve(address _spender, uint256 _value) external override returns (bool) {
        require(_spender != address(0), "Dtoken: Approve to the zero address");
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function _mint(address _to, uint256 _amount) internal returns (bool) {
        require(_to != address(0), "Dtoken: Mint to the zero address");
        balanceOf[_to] += _amount;
        totalSupply += _amount;
        emit Transfer(address(0x0), _to, _amount);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _value) internal returns (bool) {
        require(_to != address(0), "Dtoken: Transfer to the zero address");

        uint256 fromBalance = balanceOf[_from];
        require(fromBalance >= _value, "Dtoken: Transfer amount exceeds balance");
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

    function transferFrom(address _from, address _to, uint256 _value) external override returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowance[_from][spender];
        if (spenderAllowance != type(uint256).max) {
            require(spenderAllowance >= _value, "Dtoken: Insufficient allowance");
            unchecked {
                uint256 newAllowance = spenderAllowance - _value;
                allowance[_from][spender] = newAllowance;
                emit Approval(_from, spender, newAllowance);
            }
        }
        return _transfer(_from, _to, _value);
    }

    function mint(address account, uint256 amount) external returns (bool) {
        require(msg.sender == minter, "Dtoken: Not minter");
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount) public virtual {
        address account = msg.sender;

        uint256 accountBalance = balanceOf[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            balanceOf[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }
}

