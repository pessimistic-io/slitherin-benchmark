// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC721A.sol";

contract MutantHamstersToken is ERC20, Ownable {

    uint256 public immutable maxSupply;
    uint256 public claimable;

    bool public isInitialed = false; 

	mapping(address => uint256) public _rewards;
	mapping(address => uint256) public _lastUpdate;

    uint256 public immutable dailyReward;

	ERC721A public immutable _hamstersContract;

    address STAKE_POOL_ADDRESS = address(0x1F34eb9801CfD9E7cA6a97b7166d6DbaF9A6A788);

	event RewardClaimed(address indexed user, uint256 indexed reward);

    modifier InitialModifier() {
        require(!isInitialed,"already initialed");
        isInitialed = true;
        _;
    }

	constructor(address _hamsters) ERC20("Mutant Hamsters Token", "MHT") {
		_hamstersContract = ERC721A(_hamsters);
        maxSupply = 1000000000 * (10**decimals());
        dailyReward = 100*(10**decimals());
	}

    function Initial() external InitialModifier onlyOwner {
        _mint(STAKE_POOL_ADDRESS, (maxSupply/100)*20);
        claimable = maxSupply - ((maxSupply/100)*20);

    }
	

	function updateRewardOnMint(address _user) external {
        if(claimable == 0) return;
		require(msg.sender == address(_hamstersContract), "Can't call this");
		uint256 timerUser = _lastUpdate[_user];
        uint256 time = block.timestamp;
        uint256 subTime = time - timerUser;
        subTime = subTime == time ? 1: subTime;
        uint256 reward = dailyReward +_hamstersContract.balanceOf(_user)*((dailyReward / 1 days)*subTime);

        if(reward > claimable) reward = claimable;

		_rewards[_user] += reward;
        claimable -= reward;
		

		_lastUpdate[_user] = time;
	}

	// called on transfers
	function updateReward(address _from, address _to) external {
        if(claimable == 0) return;
		require(msg.sender == address(_hamstersContract), "Can't call this");

		uint256 time = block.timestamp;
		uint256 timerFrom = _lastUpdate[_from];

        uint256 subTime = time - timerFrom;
        subTime = subTime == time ? 1: subTime;

        uint256 reward = _hamstersContract.balanceOf(_from)*((dailyReward / 1 days)*subTime);

        if(reward > claimable) reward = claimable;
        

		_rewards[_from] += reward;
        claimable -= reward;

		if (_to != address(0)) {
            if(claimable == 0) return;
			uint256 timerTo = _lastUpdate[_to];
            subTime = time - timerTo;
            subTime = subTime == time ? 1: subTime;

            reward = _hamstersContract.balanceOf(_to)*((dailyReward / 1 days)*subTime);
            if(reward > claimable) reward = claimable;
			_rewards[_to] += reward;
            claimable -= reward;

			_lastUpdate[_to] = time;
		}
        _lastUpdate[_from] = time;
	}

	function getReward(address _to) external {
		require(msg.sender == address(_hamstersContract), "Can't call this");


		uint256 reward = _rewards[_to];

		if (reward > 0) {
			_rewards[_to] = 0;

			_mint(_to, reward);

			emit RewardClaimed(_to, reward);
		}
	}

    function mint(address to, uint256 amount) external onlyOwner returns(uint256) {
        if(claimable == 0) return 0;
        if(amount > claimable) amount = claimable;

        _mint(to,amount);
        claimable -= amount;
        return amount;
        
    }

	function burn(address _from, uint256 _amount) external { 
		_burn(_from, _amount);
	}

	function getTotalClaimable(address _user) external view returns(uint256) {
        if(claimable == 0) return _rewards[_user];
		uint256 time = block.timestamp;
        uint256 subTime = time - _lastUpdate[_user];
        subTime = subTime == time ? 1: subTime;
		uint256 pending = _hamstersContract.balanceOf(_user)*((dailyReward / 1 days)*subTime);
        if(pending > claimable) pending = claimable;

		return _rewards[_user] + pending;
	}
}
