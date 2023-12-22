// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./IManager.sol";
import "./SafeMath.sol";

contract ERC20 {
    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint256 public decimals = 18;
    uint256  public totalSupply;

    address public manager;
    bool public inPrivateTransferMode;
    mapping(address => bool) public isHandler;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event InPrivateTransferModeSettled(bool _inPrivateTransferMode);
    event HandlerSettled(address _handler, bool _isActive);

    constructor(address _manager){
        require(_manager != address(0), "ERC20: invalid manager");
        manager = _manager;
    }

    modifier _onlyController(){
        require(IManager(manager).checkController(msg.sender), 'Pool: only controller');
        _;
    }

    function setInPrivateTransferMode(bool _inPrivateTransferMode) external _onlyController {
        inPrivateTransferMode = _inPrivateTransferMode;
        emit InPrivateTransferModeSettled(_inPrivateTransferMode);
    }

    function setHandler(address _handler, bool _isActive) external _onlyController {
        isHandler[_handler] = _isActive;
        emit HandlerSettled(_handler, _isActive);
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(from != address(0), "ERC20: _burn from the zero address");
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: owner is the zero address");
        require(spender != address(0), "ERC20: spender is the zero address");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: _transfer from the zero address");
        require(to != address(0), "ERC20: _transfer to the zero address");

        if (inPrivateTransferMode) {
            require(isHandler[msg.sender], "ERC20: msg.sender not whitelisted");
        }

        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(from != address(0), "ERC20: transferFrom from the zero address");
        require(to != address(0), "ERC20: transferFrom to the zero address");
        if (isHandler[msg.sender]) {
            _transfer(from, to, value);
            return true;
        }

        if (allowance[from][msg.sender] != uint256(- 1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);

        return true;
    }
}

