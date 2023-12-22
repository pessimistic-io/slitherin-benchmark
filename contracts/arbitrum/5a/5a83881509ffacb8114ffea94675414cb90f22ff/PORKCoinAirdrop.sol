// SPDX-License-Identifier: GPL-3.0 

pragma solidity ^0.8.0;

interface IERC20 {
  
    function totalSupply() external view returns (uint256);

 
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

   
    event Approval(address indexed owner, address indexed spender, uint256 value);
}



pragma solidity ^0.8.2;


contract PORKCoinAirdrop {

    uint256 public total_ClaimAirdrop;
    uint256 public cost = 53 * 10 ** 13; 
    address public owner;

    IERC20 public token;
    uint256 _decimal = 9;
    uint256 public reward = 69 * 10 ** _decimal;
    uint256 public referral_reward = 0 * 10 ** _decimal;

    bool public paused = false;

    mapping(address => uint) public total_claims;
    mapping (uint => address) public _users;
    mapping(address => bool) public _claimed;

    constructor(address _token) {
        token = IERC20(_token);
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner,"Caller: Must be Owner!!");
        _;
    }

    mapping(address => uint) public dayClaim;
    mapping(address => uint256) public clock;
    //50000000
    uint256 public total_Count = 50000000 * 10 ** _decimal;
    uint256 public total_gons;
    
    mapping (address => bool) public isWhitelisted;
    bool public onlyWhitelist;

    function claimAirdrop() public payable { //(0.0012 BNB)

        require(!paused,"AirDrop is Paused!!");
        
        if(onlyWhitelist) {
            require(isWhitelisted[msg.sender],"User is not Whitelisted!");
        }

        require(total_gons <= total_Count,"Air Drop Rewards Distributed!!");

        require(msg.value >= cost,"Insufficient Funds!!");

        if(dayClaim[msg.sender] == 0 ) {
            clock[msg.sender] = block.timestamp;
        }

        if(block.timestamp <= clock[msg.sender] + 1 days ){
            require(dayClaim[msg.sender] != 5,"Daily Limit Exceeded!!");
        }

        if(dayClaim[msg.sender] == 5) {
            clock[msg.sender] = block.timestamp;
            dayClaim[msg.sender] = 0;
        }

        dayClaim[msg.sender] += 1;

        if (total_claims[msg.sender] <= 0)
        {
            _users[total_ClaimAirdrop] = msg.sender;
            total_ClaimAirdrop += 1;
        }

        total_claims[msg.sender] += msg.value;

        (bool success,) = payable(owner).call{value: msg.value}("");
        require(success,"Transaction Failed!!");

        token.transfer(msg.sender, reward);

        total_gons += reward;

        _claimed[msg.sender] = true;
        // token.transferFrom(owner(),msg.sender, reward); 
    }

    function Balance() public view returns(uint256){
        return address(this).balance;
    }

    function token_Balance() public view returns(uint256){
        return token.balanceOf(address(this));
    }

    function setRewards(uint _ClaimReward, uint _referralReward) external onlyOwner{
        reward = _ClaimReward;
        referral_reward = _referralReward;
    }

    function withdraw() public onlyOwner {
        (bool success,) = payable(owner).call{value: address(this).balance}("");
        require(success,"Transaction Failed!!");
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function setCost(uint _amount) public onlyOwner{
        cost = _amount;
    }

    function setPaused(bool _value) external onlyOwner{
        paused = _value;
    }
    
    function setDecimals(uint _value) external onlyOwner{
        _decimal = _value;
    }

    function setAirMax(uint _value) external onlyOwner{
        total_Count = _value;
    }

    function enableWhitelist(bool _status) external onlyOwner {
        onlyWhitelist = _status;
    }
   
    function addOrRemoveWhitelist(address[] calldata _adr, bool _status) external onlyOwner {
        uint length = _adr.length;
        for(uint i = 0; i < length; i++) {
            isWhitelisted[_adr[i]] = _status;
        }
    }
	
	function transferOwnership(address _newOwner) external onlyOwner{
		owner = _newOwner;
	}

    
}