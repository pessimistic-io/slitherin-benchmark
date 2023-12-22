// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./ERC20Detailed.sol";
import "./Ownable.sol";
import "./SafeMathInt.sol";

/**
 * @title Ranbased ERC20 token
 */
contract RanbasedToken is ERC20Detailed, Ownable {
    using SafeMath for uint;
    using SafeMathInt for int;

    event LogRebase(uint indexed epoch, uint totalSupply);

    // Used for authentication
    address public controller;

    modifier onlyController() {
        require(msg.sender == controller);
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    uint private constant DECIMALS = 9;
    uint private constant MAX_UINT256 = type(uint).max;
    uint private constant INITIAL_FRAGMENTS_SUPPLY =   50 * 10**6 * 10**DECIMALS;

    uint private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    uint private constant MAX_SUPPLY = type(uint128).max;  // (2^128) - 1

    uint private _totalSupply;
    uint private _gonsPerFragment;
    mapping(address => uint) private _gonBalances;

    mapping (address => mapping (address => uint)) private _allowedFragments;

    bool public PAUSED;
    bool public MAX_TRANSACTION_LIMIT_STATUS;
    uint public MAX_WALLET_SIZE;
    uint public MAX_TX_SIZE;

    address public RANB_WETH_pair;

    function rebase(uint epoch, int supplyDelta) external onlyController returns (uint)
    {
        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint(supplyDelta.abs()));
        } else {
            _totalSupply = _totalSupply.add(uint(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }

    constructor()
        ERC20Detailed("Ranbased", "RANB", uint8(DECIMALS))
    {
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonBalances[msg.sender] = TOTAL_GONS;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        MAX_WALLET_SIZE = (_totalSupply * 2) / 1000;
        MAX_TX_SIZE = (_totalSupply * 75) / 100000;
        
        MAX_TRANSACTION_LIMIT_STATUS = false;
        PAUSED = true;

        emit Transfer(address(0x0), msg.sender, _totalSupply);
    }

    function setController(address _controller) external onlyOwner {
        controller = _controller;
    }
    function setMaxTransactionLimitStatus(bool _status) external onlyOwner {
        MAX_TRANSACTION_LIMIT_STATUS = _status;
    }
    function setPair(address _pair) external onlyOwner {
        RANB_WETH_pair = _pair;
    }
    function setPaused(bool _status) external onlyOwner{
        PAUSED = _status;
    }

    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address who) external view returns (uint)
    {
        return _balanceOf(who);
    }
    function _balanceOf(address who) private view returns (uint) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    function transfer(address to, uint value)
        external
        validRecipient(to)
        returns (bool)
    {
        return _transferFrom(_msgSender(),to,value);
    }
 

    function allowance(address owner_, address spender)
        external
        view
        returns (uint)
    {
        return _allowedFragments[owner_][spender];
    }

    function transferFrom(address from, address to, uint value)
        external
        validRecipient(to)
        returns (bool)
    {
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        return _transferFrom(from,to,value);
    }
   function _transferFrom(address from, address to, uint value) private returns (bool) 
   {
        require(!PAUSED || from == owner() || to == owner(),"transfers paused.!");
        require(!MAX_TRANSACTION_LIMIT_STATUS || checkMaxLimits(from, to, value),"Transfer amount exceeds max wallet size or tx size.");

        uint gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        
        emit Transfer(from, to, value);
        return true;
    }
    function checkMaxLimits(address _from, address _to, uint _value) private view returns (bool) {
        if (_from == owner() || _to == owner() || _to == RANB_WETH_pair) return true;
        return (_value <= MAX_TX_SIZE && _balanceOf(_to) + _value <= MAX_WALLET_SIZE);
    }
    function approve(address spender, uint value)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint addedValue)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] =
            _allowedFragments[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint subtractedValue)
        external
        returns (bool)
    {
        uint oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

   function bulkTransfer(address[] calldata _receivers, uint[] calldata _amounts) external {
		require(_receivers.length == _amounts.length);
		for (uint i = 0; i < _receivers.length; i++) {
			require(_transferFrom(_msgSender(), _receivers[i], _amounts[i]));
        }
    }
}
