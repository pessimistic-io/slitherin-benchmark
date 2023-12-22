// SPDX-License-Identifier: MIT

/* Author : BOBSEAL */

pragma solidity ^0.8.17;
import "./SafeMath.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";

contract SedPepe is IERC20 , ReentrancyGuard {
      // TYPES DEFINITIONS
    using SafeMath for uint256;

    // state variables
    string public constant name = "Sed Pepe";
    string public constant symbol = "SPEPE";
    uint256 public constant decimals = 18;
    uint256 public fee1;
    uint256 public fee2;
    uint256 public fee3;
    address private address1;
    address private address2;
    address private burnAddress;
    uint256 private maxTx; //max transaction limit
    uint256 private _totalSupply;
    bool private lockedSwap; //StoreLockSwapStatus

    address private Owner; //owner

    // mappings
    mapping(address => uint256) private _balances; // balance mapping
    mapping(address => mapping(address => uint256)) private _allowances; //allowance mapping
    mapping(address => bool) private _isExcludedFromFee; //fee exclusion mapping
    mapping(address => bool) private _excludedFromTxLimit; // max tx Limit

    // events -- name defines the event comments unneeded
    event ExcludeFromFee(address indexed account, bool isExcluded);
    event SetFeePercentage(uint256 feePercentage , uint256 timestamp);
    event TransferOwnership(address indexed previousOwner , address indexed newOwner , uint256 timestamp);
    event TransactionStatus(bool TransactionsEnabled , uint256 timestamp);

    //Constructor
    /* 
    Basis Fee : 1 = 0.01 %

    Basis Tx and Wallet Limit : 1 = 1%
    */

    constructor( uint256 tottalsupply , uint256 _fee1 , uint256 _fee2 , uint256 _fee3 ,
     uint256 _MaxTx , address eco_wallet , address reward_wallet , address treasuryWallet) {
        _totalSupply = tottalsupply * (10**decimals);
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
        address1 = eco_wallet ; // Ecosystem Fee
        address2 = reward_wallet ; // Liquidity Fee
        burnAddress = address(0); // burn this amount
        fee1 = _fee1;  
        fee2 = _fee2;
        fee3 = _fee3;
        maxTx= _MaxTx;
        Owner = msg.sender;
        lockedSwap = false;
        excludeFromAll(msg.sender , eco_wallet , reward_wallet , treasuryWallet);
    }

    /*
    View / Getter Functions
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

     function totalUnburntSupply() public view returns (uint256) {
        uint256 totSupply = _totalSupply - _balances[burnAddress];
        return totSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owwner, address spender) public view returns (uint256) {
        return _allowances[owwner][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function owner() public view returns (address) {
        return Owner;
    }

    function isApproved(address account) public view returns (bool) {
        return _allowances[account][owner()] > 0;
    }

    /*
    Checks if wallet is Excluded from  Fee Mechanism

    returns bool
    */
    
    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }
    
    /*
    Checks if wallet is Excluded from TX limit

    returns bool
    */

    function isExcludedFromTxLimit(address account) public view returns(bool){
        return _excludedFromTxLimit[account];
    }

    /*
    Checks if Swap is locked

    returns bool
    */

    function CheckIfSwapLocked() public view returns(bool){
        return lockedSwap;
    }

     /*
      * @dev transfer token 
      * @param recipient => the token recipient
      * @param amount => tokenAmount
      * returns bool
    */

    function transfer(address recipient, uint256 amount) public returns (bool) {
        if (_isExcludedFromFee[msg.sender]) {
            _transfer(msg.sender, recipient, amount);
        }else{
            uint256 feeAmount1 = amount.mul(fee1).div(10000);
            uint256 feeAmount2 = amount.mul(fee2).div(10000);
            uint256 feeAmount3 = amount.mul(fee3).div(10000);
            uint256 totalFee = feeAmount1.add(feeAmount2).add(feeAmount3);
            uint256 amtAfterFee = amount.sub(totalFee);

            //transfer applicable fee and transfers tokens after fee to reciever

            _transfer(msg.sender, recipient, amtAfterFee);
            _transfer(msg.sender, address1, feeAmount1); 
            _transfer(msg.sender, address2, feeAmount2);
            _transfer(msg.sender, burnAddress, feeAmount3);
        }
        return true;
    }


    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _allowances[sender][msg.sender] = currentAllowance.sub(amount);
        if (_isExcludedFromFee[msg.sender]) {
            _transfer(sender, recipient, amount);
        } else {
            uint256 feeAmount1 = amount.mul(fee1).div(1000);
            uint256 feeAmount2 = amount.mul(fee2).div(1000);
            uint256 feeAmount3 = amount.mul(fee3).div(1000);
            uint256 totalFee = feeAmount1.add(feeAmount2).add(feeAmount3);
            uint256 amtAfterFee = amount.sub(totalFee);
            _transfer(sender, recipient, amtAfterFee);
            _transfer(sender, address1, feeAmount1);
            _transfer(sender, address2, feeAmount2);
            _transfer(sender, burnAddress, feeAmount3);
        }
        return true;
    }


    function _transfer(address sender, address recipient, uint256 amount) internal nonReentrant {
        require(lockedSwap == false ,"Transacitons are temporarily disabled for this token");

        //checks for exceptions
        if (!_excludedFromTxLimit[msg.sender]){
        require(amount <= _totalSupply.mul(maxTx).div(100),"Amount Exceeds Allowed Transaction Limit, Retry or get Permission");
        }
        require(_balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    //Burn Function

    function burn(uint256 amount) public returns(bool) {
        require(_balances[msg.sender] >= amount, "ERC20: burn amount exceeds balance");
        _balances[msg.sender] -= amount;
        _balances[address(0)] += amount;
        emit Transfer(msg.sender, address(0), amount);
        return true;
    }


    //DAO Functions to Set Fee and Fee Reciever

    function setFee(uint256 _fee1, uint256 _fee2 , uint256 _fee3) public returns(bool) {
        require(msg.sender == owner(), "Only the owner can set the fee");
        fee1 = _fee1;
        fee2 = _fee2;
        fee3 = _fee3;
        emit SetFeePercentage(_fee1 + _fee2 + _fee3 , block.timestamp);
        return true;
    }

    function setFeeAddress(address _address1, address _address2) public returns(bool) {
        require(msg.sender == owner(), "Only the owner can set the address");
        address1 = _address1;
        address2 = _address2;
        return true;
    }

    //DAO Functions to set Limits and Exceptions
    function excludeFromFee(address account) public returns(bool){
        require(msg.sender == owner(), "Only the owner can exclude addresses from fees");
        require(_isExcludedFromFee[account] == false ,"account already excluded");
        _isExcludedFromFee[account] = true;
        emit ExcludeFromFee(account, true);
        return true;
    }


    function includeInFee(address account) public returns(bool) {
        require(msg.sender == owner(), "Only the owner can exclude addresses from fees");
        require(_isExcludedFromFee[account] == true ,"account already included");
        _isExcludedFromFee[account] = false;
        emit ExcludeFromFee(account, false);
        return true;
    }


    function excludeFromTxLimit(address account) public returns(bool){
        require(msg.sender == owner(), "Only Owner Is allowed to call");
        require(_excludedFromTxLimit[account] == false , "account already excluded");
        _excludedFromTxLimit[account] = true;
        return true;
    }


    function includeInTxLimit(address account) public returns(bool){
        require(msg.sender == owner(), "Only Owner Is allowed to call");
        require(_excludedFromTxLimit[account] == true , "account already included");
        _excludedFromTxLimit[account] = false;
        return true;
    }

    //Transfer Ownership

    function transferOwnership(address newOwner) public returns(bool){
        require (msg.sender == Owner,"OnlyOwner can do this");
        address oldOwner = Owner;
        Owner = newOwner;
        emit TransferOwnership(oldOwner , newOwner , block.timestamp);
        return true;
    }

    //DAO functions to Lock , Unlock swap and change limits

    function lockSwap() public returns(bool){
        require (msg.sender == Owner , "Cant Lock , needs to be owner");
        require(lockedSwap == false);
        lockedSwap = true;
        emit TransactionStatus(false , block.timestamp);
        return true;
    }

    function unlockSwap() public returns(bool){
        require (msg.sender == Owner , "Cant Lock , needs to be owner");
        require(lockedSwap == true);
        lockedSwap = false;
        emit TransactionStatus(true , block.timestamp);
        return true;
    }
    
    function changeMaxTxLimit(uint256 newLimit) external returns(bool){
        require (msg.sender == Owner , "Cant Change, needs to be owner");
        maxTx = newLimit;
        return true;
    }
    //constructor function 

    function excludeFromAll(address a , address b , address c , address d) internal {
        _isExcludedFromFee[a] = true;
        _isExcludedFromFee[b] = true;
        _isExcludedFromFee[c] = true;
        _isExcludedFromFee[d] = true;
        _excludedFromTxLimit[a]=true;
        _excludedFromTxLimit[b]=true;
        _excludedFromTxLimit[c]=true;
        _excludedFromTxLimit[d]=true;
    }
   
}
