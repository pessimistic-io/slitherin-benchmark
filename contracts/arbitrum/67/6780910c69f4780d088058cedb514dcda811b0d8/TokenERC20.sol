// SPDX-licence-identifier : MIT

/* Author : BOBSEAL */

pragma solidity ^0.8.17;
import "./SafeMath.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";

contract BUFFFinal is IERC20 , ReentrancyGuard {
      // TYPES DEFINITIONS
    using SafeMath for uint256;

    // state variables
    string public name;
    string public symbol;
    uint256 public constant decimals = 18;
    uint256 public fee1;
    uint256 public fee2;
    uint256 public fee3;
    address private address1;
    address private address2;
    address private burnAddress;
    uint256 private maxTx; //max transaction limit
    uint256 private maxHoldLimit; // max limit per wallet to hold
    uint256 private _totalSupply;
    bool private lockedSwap; //StoreLockSwapStatus

    address private Owner; //owner

    // mappings
    mapping(address => uint256) private _balances; // balance mapping
    mapping(address => mapping(address => uint256)) private _allowances; //allowance mapping
    mapping(address => bool) private _isExcludedFromFee; //fee exclusion mapping
    mapping(address => bool) private _excludedFromHoldLimit; // max wallet balance limit
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

    constructor(string memory _name , string memory _ssymbol , uint256 tottalsupply , address _reciever1 , address _reciever2 , uint256 _fee1 , uint256 _fee2 , uint256 _fee3 , uint256 maxHLimit , uint256 _MaxTx ) {
        _totalSupply = tottalsupply * (10**18);
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
        //Temporary Addresses To recieve ... Will be canged to Multisigs
        address1 = _reciever1 ; // fee recieving wallets ... Ecosystem MultiSig Wallet for the Ecosystem Revenue and Run Costs
        address2 = _reciever2 ; // Ecosystem Multisig Reward and Incentive Pool
        burnAddress = address(0); // burn this amount
        fee1 = _fee1;  
        fee2 = _fee2;
        fee3 = _fee3;
        maxTx= _MaxTx;
        name= _name;
        symbol= _ssymbol;
        maxHoldLimit =maxHLimit ;
        Owner = msg.sender;
        lockedSwap = false;
        excludeFromFee(msg.sender);
        excludefromHoldLimit(msg.sender);
        excludeFromTxLimit(msg.sender);
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
    Checks if wallet is Excluded from Wallet Balance limit

    returns bool
    */
    
    function isExcludedFromHoldLimit(address account) public view returns(bool){
        return _excludedFromHoldLimit[account];
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
        uint256 outAmt= _totalSupply.mul(maxTx).div(100);
        uint256 senderLim = _totalSupply.mul(maxHoldLimit).div(100);

        //checks for exceptions
        if (!_excludedFromTxLimit[msg.sender]){
        require(amount <= outAmt,"Amount Exceeds Allowed Transaction Limit, Retry or get Permission");
        }

        if(!_excludedFromHoldLimit[msg.sender]){
        require (_balances[recipient].add(amount) < senderLim , "The Reciever Balance is already max of what is allowed to hold");
        }

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance.sub(amount);
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


    //Admin Functions to Set Fee and Fee Reciever

    function setFee(uint256 _fee1, uint256 _fee2, uint256 _fee3) public returns(bool) {
        require(msg.sender == owner(), "Only the owner can set the fee");
        fee1 = _fee1;
        fee2 = _fee2;
        fee3 = _fee3;
        emit SetFeePercentage(_fee1 + _fee2 + _fee3 , block.timestamp);
        return true;
    }

    function setFeeAddress(address _address1, address _address2, address _address3) public returns(bool) {
        require(msg.sender == owner(), "Only the owner can set the address");
        address1 = _address1;
        address2 = _address2;
        burnAddress = _address3;
        return true;
    }

    //Admin Functions to set Limits and Exceptions
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

    function excludefromHoldLimit(address account) public returns(bool) {
        require (msg.sender == owner() , "Only Owner Function");
        require(_excludedFromHoldLimit[account] == false , "Already Excluded");
        _excludedFromHoldLimit[account] = true;
        return true;
    }


    function includeInHoldLimit(address account) public returns(bool){
        require (msg.sender == owner() , "Only Owner Function");
        require(_excludedFromHoldLimit[account] == true , "Already Included");
        _excludedFromHoldLimit[account] = false;
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

    //Admin Functions to Lock and Unlock swap

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
    //change limits

    function changeMaxTxLimit(uint256 newLimit) external returns(bool){
        require (msg.sender == Owner , "Cant Change, needs to be owner");
        maxTx = newLimit;
        return true;
    }
    function changeMaxHoldLimit(uint256 newLimit) external returns(bool){
        require (msg.sender == Owner , "Cant Change, needs to be owner");
        maxHoldLimit = newLimit;
        return true;
    }
}
