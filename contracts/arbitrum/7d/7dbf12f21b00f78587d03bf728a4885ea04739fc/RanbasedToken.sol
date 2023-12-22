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

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint for max granularity.
    uint private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint private constant MAX_SUPPLY = type(uint128).max;  // (2^128) - 1

    uint private _totalSupply;
    uint private _gonsPerFragment;
    mapping(address => uint) private _gonBalances;

    // This is denominated in Fragments, because the gons-fragments conversion might change before
    // it's fully paid.
    mapping (address => mapping (address => uint)) private _allowedFragments;

    bool public PAUSED;
    bool public MAX_TRANSACTION_LIMIT_STATUS;
    uint public MAX_WALLET_SIZE;
    uint public MAX_TX_SIZE;

    address public RANB_WETH_pair;
    /**
     * @dev Notifies Fragments contract about a new rebase cycle.
     * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
     * @return The total number of fragments after the supply adjustment.
     */
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
        
        MAX_TRANSACTION_LIMIT_STATUS = true;
        PAUSED = true;

        emit Transfer(address(0x0), msg.sender, _totalSupply);
    }

    /**
     * @notice Sets a new controller
     */
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
    /**
     * @return The total number of fragments.
     */
    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) external view returns (uint)
    {
        return _balanceOf(who);
    }
    function _balanceOf(address who) private view returns (uint) {
        return _gonBalances[who].div(_gonsPerFragment);
    }
    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint value)
        external
        validRecipient(to)
        returns (bool)
    {
        /*
        uint gonValue = value.mul(_gonsPerFragment);
        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        emit Transfer(msg.sender, to, value);
        return true;
        */
        return _transferFrom(_msgSender(),to,value);
    }
 
    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender)
        external
        view
        returns (uint)
    {
        return _allowedFragments[owner_][spender];
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
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
        if(PAUSED){
            require(from == owner() || to == owner(),"transfers paused.!");
        }        

        if(MAX_TRANSACTION_LIMIT_STATUS){
            if (from != owner() && to != owner() && to != RANB_WETH_pair) {           
                require((value <= MAX_TX_SIZE && _balanceOf(to) + value <= MAX_WALLET_SIZE), "Transfer amount exceeds the MaxWallet size.");
            }
        }

        uint gonValue = value.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        
        emit Transfer(from, to, value);
        return true;
    }
    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint value)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint addedValue)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] =
            _allowedFragments[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
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
    /*
    function bulkTransfer(address[] calldata _receivers, uint[] calldata _amounts) external {
		require(_receivers.length == _amounts.length);
		for (uint i = 0; i < _receivers.length; i++) {
			require(_transferFrom(_msgSender(), _receivers[i], _amounts[i]));
        }
    }
    */
}
