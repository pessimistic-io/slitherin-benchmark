// SPDX-License-Identifier: MIT

pragma solidity >=0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";


contract VestingContract {

    using SafeERC20 for IERC20;


    uint256 constant public PRECISION = 5000;
    uint256 immutable START_VESTING;
    uint256 immutable DURATION;
    bool configured;

    address public owner;
    
    IERC20 public token;


    uint public claimableAmount;
    uint public amountClaimed;
    address public receiver;


    modifier onlyOwner {
        require(msg.sender == owner, 'not owner');
        _;
    }

    event Deposit(uint256 amount, address receiver);
    event Claimed(address _who, uint amount);


    constructor(address _token) {
        owner = address(0x25eC5c30bf75BF0BD7D80dfa31709B6038b16761);
        token = IERC20(_token);
        START_VESTING = 1684972800;   //GMT: MAY 25, 2023 12:00:00 AM
        DURATION = 8 * 604800; //2 months
    }

    /* 
        OWNER FUNCTIONS
    */

    function deposit(uint256 amount, address _receiver) external {
        
        require(msg.sender == owner);
        require(!configured, "Vesting already configured");

        token.safeTransferFrom(msg.sender, address(this), amount);
        claimableAmount = amount;
        receiver = _receiver;

        configured = true;
        emit Deposit(amount, _receiver);
    }
    

    function setOwner(address _owner) external onlyOwner{
        owner = _owner;
    }

    /* 
        Receiver FUNCTIONS
    */

    function claim() public {
        require(receiver == msg.sender, "Not the receiver of the vesting");
        require(claimableAmount != amountClaimed,"Already claimed");

        if (block.timestamp > START_VESTING) {
            uint amount = claimableAmount;

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > DURATION) timeElapsed = DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / DURATION;
                
            uint amountToReceive = (amount * percentToReceive / PRECISION) - amountClaimed;
                
            amountClaimed += amountToReceive;

            token.transfer(msg.sender, amountToReceive);

            emit Claimed (msg.sender, amountToReceive);

            
        }
    }

    fallback() external {
        claim();
    }

}
