//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./SafeMath.sol";

// [X] Anyone can contribute
// [X] End project if targeted contribution amount reached
// [X] Expire project if raised amount not fullfill between deadline
//    & return donated amount to all contributor .

contract GMARBCrowdFunding is Ownable{

    using SafeMath for uint256;

    enum State {
        Fundraising,
        Expired,
        Successful
    }

    string public projectTitle;
    string public projectDes;
    uint256 public minimumContribution; 
    uint256 public targetContribution; 
    uint256 public deadline;
    uint public completeAt;
    uint256 public raisedAmount; 
    uint256 public noOfContributers;
    
    State public state = State.Fundraising; 

    mapping (address => uint) public contributiors;

    modifier validateExpiry(State _state){
        require(state == _state,'Invalid state');
        require(block.timestamp < deadline,'Deadline has passed !');
        _;
    }

    event FundingReceived(address contributor, uint amount, uint currentTotal);

    constructor() {
        projectTitle = "GM ARB Crowd Funding";
        projectDes = "GM ARB Crowd Funding";
        minimumContribution = 1000000000000000; // 0.001 ETH
        targetContribution = 10000000000000000000; // 10 ETH
        deadline = 1685278800;
        raisedAmount = 0;
   }

    function contribute(address _contributor) public validateExpiry(State.Fundraising) payable {
        require(msg.value >= minimumContribution,'Contribution amount is too low !');
        if(contributiors[_contributor] == 0){
            noOfContributers++;
        }
        contributiors[_contributor] += msg.value;
        raisedAmount = raisedAmount.add(msg.value);
        emit FundingReceived(_contributor,msg.value,raisedAmount);
        checkFundingCompleteOrExpire();
    }

    function checkFundingCompleteOrExpire() internal {
        if(raisedAmount >= targetContribution){
            state = State.Successful; 
        }else if(block.timestamp > deadline){
            state = State.Expired; 
        }
        completeAt = block.timestamp;
    }

    function requestRefund() public validateExpiry(State.Expired) returns(bool) {
        require(contributiors[msg.sender] > 0,'You dont have any contributed amount !');
        address payable user = payable(msg.sender);
        user.transfer(contributiors[msg.sender]);
        contributiors[msg.sender] = 0;
        return true;
    }

    function extendDeadline(uint256 newDeadline) public onlyOwner {
       deadline = newDeadline;
    }

    function withdrawFunds() public onlyOwner{
       uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        address payable ownerAddress = payable(owner());
        ownerAddress.transfer(balance);
    }

    function getProjectDetails() public view returns(
    uint256 minContribution,
    uint256  projectDeadline,
    uint256 goalAmount, 
    uint completedTime,
    uint256 currentAmount, 
    string memory title,
    string memory desc,
    State currentState,
    uint256 balance
    ){
        minContribution=minimumContribution;
        projectDeadline=deadline;
        goalAmount=targetContribution;
        completedTime=completeAt;
        currentAmount=raisedAmount;
        title=projectTitle;
        desc=projectDes;
        currentState=state;
        balance=address(this).balance;
    }

    receive() external payable {}
}
