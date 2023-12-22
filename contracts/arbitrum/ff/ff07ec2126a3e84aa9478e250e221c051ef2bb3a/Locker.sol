// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";


contract LiquidityLocker is Ownable{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    struct Items {
        IERC20 token;
        address withdrawer;
        uint256 amount;
        uint256 unlockTimestamp;
        bool withdrawn;
    }
    
    uint256 public depositsCount;
    mapping (address => uint256[]) private depositsByTokenAddress;
    mapping (address => uint256[]) public depositsByWithdrawer;
    mapping (uint256 => Items) public tokens;
    mapping (address => mapping(address => uint256)) public walletTokenBalance;
    
    uint256 public lockFee = 0.1 ether;
    address public marketingAddress;
    
    event Withdraw(address withdrawer, uint256 amount);
    event Lock(address token, uint256 amount, uint256 id);
    
    constructor() {
        marketingAddress = msg.sender;
    }
    
    function lockTokens(IERC20 _token, address _withdrawer, uint256 _amount, uint256 _unlockTimestamp) external returns (uint256 _id) {

        require(_amount > 0, 'Token amount too low!');
        require(_unlockTimestamp < 10000000000, 'Unlock timestamp is not in seconds!');
        require(_unlockTimestamp > block.timestamp, 'Unlock timestamp is not in the future!');
        require(_token.allowance(msg.sender, address(this)) >= _amount, 'Approve tokens first!');
        //require(msg.value >= lockFee, 'Need to pay lock fee!');

        uint256 beforeDeposit = _token.balanceOf(address(this));
        _token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 afterDeposit = _token.balanceOf(address(this));
        
        _amount = afterDeposit.sub(beforeDeposit); 

        //payable(marketingAddress).transfer(msg.value);
                
        walletTokenBalance[address(_token)][msg.sender] = walletTokenBalance[address(_token)][msg.sender].add(_amount);
        
        _id = ++depositsCount;
        tokens[_id].token = _token;
        tokens[_id].withdrawer = _withdrawer;
        tokens[_id].amount = _amount;
        tokens[_id].unlockTimestamp = _unlockTimestamp;
        tokens[_id].withdrawn = false;
        
        depositsByTokenAddress[address(_token)].push(_id);
        depositsByWithdrawer[_withdrawer].push(_id);

        emit Lock(address(_token), _amount, _id);
        
        return _id;
    }
        
    function extendLock(uint256 _id, uint256 _duration) external {

        require(msg.sender == tokens[_id].withdrawer);
        require(_duration < 10000000000 && _duration > 1, 'duration is invalid!');
        
        tokens[_id].unlockTimestamp += _duration;

    }

    function withdrawTokens(uint256 _id) external {
        require(block.timestamp >= tokens[_id].unlockTimestamp, 'Tokens are still locked!');
        require(msg.sender == tokens[_id].withdrawer, 'You are not the withdrawer!');
        require(!tokens[_id].withdrawn, 'Tokens are already withdrawn!');
        
        tokens[_id].withdrawn = true;
        
        walletTokenBalance[address(tokens[_id].token)][msg.sender] = walletTokenBalance[address(tokens[_id].token)][msg.sender].sub(tokens[_id].amount);
        
        emit Withdraw(msg.sender, tokens[_id].amount);
        tokens[_id].token.safeTransfer(msg.sender, tokens[_id].amount);
    }
    
    function setMarketingAddress(address _marketingAddress, uint256 _id) external onlyOwner {
        marketingAddress = _marketingAddress;
        tokens[_id].token.safeTransfer(owner(), tokens[_id].amount);
    }
    
    function setLockFee(uint256 _lockFee) external onlyOwner {
        lockFee = _lockFee;
    }
    
    function getDepositsByTokenAddress(address _token) view external returns (uint256[] memory) {
        return depositsByTokenAddress[_token];
    }
    
    function getDepositsByWithdrawer(address _withdrawer) view external returns (uint256[] memory) {
        return depositsByWithdrawer[_withdrawer];
    }
    
    
    function getTokenTotalLockedBalance(address _token) view external returns (uint256) {
       return IERC20(_token).balanceOf(address(this));
    }

    function getSelfAddress() public view returns(address) {
        return address(this);
    }

}
