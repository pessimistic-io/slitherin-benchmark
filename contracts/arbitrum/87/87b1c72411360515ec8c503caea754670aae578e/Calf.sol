// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.17;

//---------------------------------------------------------
// Imports
//---------------------------------------------------------
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ITokenXBaseV3.sol";
import "./ICakeBaker.sol";

//---------------------------------------------------------
// Contract
//---------------------------------------------------------
contract Calf is ReentrancyGuard, Pausable
{
	using SafeERC20 for IERC20;

	struct UserPhaseInfo
	{
		uint256 staked_amount;
		uint256 received_reward_amount;
	}

	struct PhaseInfo
	{
		uint256 total_staked_amount;
		uint256 start_block_id;
		uint256 end_block_id;
		uint256 reward_amount_per_share_e12;
	}

	uint256 public constant MAX_PHASE_INTERVAL_BLOCK_COUNT = 100000;

	address public address_operator;
	address public address_token_stake;
	address public address_token_reward;

	uint256 public reward_amount_per_phase;
	uint256 public phase_interval_block_count;
	uint256 public phase_start_block_id;

	PhaseInfo[] public phase_info; // phase_serial / phase_info

	// phase_serial / user_adddress / user_info
	mapping(uint256 => mapping(address => UserPhaseInfo)) public user_phase_info;

	//---------------------------------------------------------------
	// Front-end connectors
	//---------------------------------------------------------------
	event SetOperatorCB(address indexed operator, address _new_address);
	event DepositCB(address indexed _user, uint256 _pool_id, uint256 _amount);
	event ClaimCB(address indexed _user, uint256 _pool_id, uint256 _amount);
	event ClaimtNotYetCB(address indexed _user, uint256 _pool_id, uint256 _amount);
	event HandleStuckCB(address indexed _user, uint256 _amount);

	//---------------------------------------------------------------
	// Modifier
	//---------------------------------------------------------------
	modifier onlyOperator() { require(msg.sender == address_operator, "onlyOperator: Not authorized"); _; }

	//---------------------------------------------------------------
	// External Method
	//---------------------------------------------------------------
	constructor(address _address_token_stake, address _address_token_reward)
	{
		address_operator = msg.sender;
		address_token_stake = _address_token_stake;
		address_token_reward = _address_token_reward;
	}

	function set_phase(uint256 _phase_start_block_id, uint256 _phase_count, uint256 _phase_interval_block_count, uint256 _reward_amount_per_phase) external 
		onlyOperator whenPaused
	{
		require(phase_info.length == 0, "set_phase: Already called");
		require(_phase_count > 0, "set_phase: Wrong phase count");
		require(_phase_interval_block_count <= MAX_PHASE_INTERVAL_BLOCK_COUNT, "set_phase: Wrong interval value");

		phase_start_block_id = block.number > _phase_start_block_id? block.number : _phase_start_block_id;
		phase_interval_block_count = _phase_interval_block_count;
		reward_amount_per_phase = _reward_amount_per_phase;

		for(uint256 i=0; i<_phase_count; i++)
		{
			uint256 start_block = phase_start_block_id + (phase_interval_block_count * i);

			phase_info.push(PhaseInfo({
				total_staked_amount: 0,
				reward_amount_per_share_e12: 0,
				start_block_id: start_block,
				end_block_id: start_block + phase_interval_block_count
			}));
		}
				
		// Mint reward token -> Calf
		uint256 total_reward_amount = _reward_amount_per_phase * _phase_count;
		ITokenXBaseV3 reward_token = ITokenXBaseV3(address_token_reward);
		reward_token.mint(address(this), total_reward_amount);
	}

	function deposit(uint256 _phase_serial, uint256 _amount) public whenNotPaused nonReentrant
	{
		require(_phase_serial < phase_info.length, "deposit: Wrong phase serial");

		address address_user = msg.sender;

		if(_amount > 0)
		{
			PhaseInfo storage phase = phase_info[_phase_serial];
			UserPhaseInfo storage user = user_phase_info[_phase_serial][address_user];
		
			// User -> Calf(locked forever)
			IERC20 lp_token = IERC20(address_token_stake);
			lp_token.safeTransferFrom(address_user, address(this), _amount);

			// Write down deposit amount on Calf's ledger
			user.staked_amount += _amount;
			phase.total_staked_amount += _amount;

			// rebalance rewards
			phase.reward_amount_per_share_e12 = reward_amount_per_phase * 1e12 / phase.total_staked_amount;
		}

		emit DepositCB(address_user, _phase_serial, _amount);
	}

	function claim(uint256 _phase_serial) public nonReentrant
	{
		require(_phase_serial < phase_info.length, "claim: Wrong phase serial");

		address address_user = msg.sender;
		uint256 pending_reward = get_pending_reward_amount(_phase_serial, address_user);

		PhaseInfo storage phase = phase_info[_phase_serial];
		if(block.number > phase.end_block_id)
		{
			UserPhaseInfo storage user = user_phase_info[_phase_serial][address_user];

			_safe_reward_transfer(address_user, pending_reward);
			user.received_reward_amount += pending_reward;
			emit ClaimCB(address_user, _phase_serial, pending_reward);
		}
		else
			emit ClaimtNotYetCB(address_user, _phase_serial, pending_reward);
	}

	function get_pending_reward_amount(uint256 _phase_serial, address _address_user) public view returns(uint256)
	{
		require(_phase_serial < phase_info.length, "get_pending_reward_amount: Wrong phase serial");

		PhaseInfo storage phase = phase_info[_phase_serial];
		UserPhaseInfo storage user = user_phase_info[_phase_serial][_address_user];

		uint256 reward_total = (user.staked_amount * phase.reward_amount_per_share_e12) / 1e12;
		return reward_total - user.received_reward_amount;
	}

	function handle_stuck(address _address_token, uint256 _amount) public onlyOperator nonReentrant
	{
		require(_address_token != address_token_reward, "handle_stuck: Wrong token address");
		require(_address_token != address_token_stake, "handle_stuck: Wrong token address");

		address address_user = msg.sender;

		IERC20 stake_token = IERC20(_address_token);
		stake_token.safeTransfer(address_user, _amount);
		
		emit HandleStuckCB(address_user, _amount);
	}

	//---------------------------------------------------------------
	// Variable Interfaces
	//---------------------------------------------------------------		
	function set_operator(address _new_address) external onlyOperator
	{
		require(_new_address != address(0), "set_operator: Wrong address");
		address_operator = _new_address;
		emit SetOperatorCB(msg.sender, _new_address);
	}

	function get_phase_count() external view returns(uint256)
	{
		return phase_info.length;
	}

	function pause() external onlyOperator
	{ 
		_pause(); 
	}
	
	function resume() external onlyOperator
	{ 
		_unpause();
	}

	//---------------------------------------------------------------
	// Internal Method
	//---------------------------------------------------------------
	function _safe_reward_transfer(address _to, uint256 _amount) internal
	{
		IERC20 reward_token = IERC20(address_token_reward);
		uint256 cur_reward_balance = reward_token.balanceOf(address(this));

		if(_amount > cur_reward_balance)
			reward_token.safeTransfer(_to, cur_reward_balance);
		else
			reward_token.safeTransfer(_to, _amount);
	}

	function _get_cur_phase_by_block() internal view returns(uint256)
	{
		if(phase_start_block_id == 0 || block.number < phase_start_block_id)
			return 0;
		else
			return (block.number - phase_start_block_id)/phase_interval_block_count;
	}
}

