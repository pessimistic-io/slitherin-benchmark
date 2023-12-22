// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.17;

//---------------------------------------------------------
// Imports
//---------------------------------------------------------
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

//---------------------------------------------------------
// Interface
//---------------------------------------------------------
interface IWETH
{
	function deposit() external payable;
	function withdraw(uint256) external;
}

//---------------------------------------------------------
// Contract
//---------------------------------------------------------
contract Chick is ReentrancyGuard
{
	using SafeERC20 for IERC20;

	address public constant ADDRESS_BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
	address public constant ADDRESS_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
	address public constant ADDRESS_PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

	address public address_operator;
	address public address_arrow_token;
	address public address_target_token;

	address public address_vault;
	uint256 public bnb_per_busd_vault_ratio_e6 = 490100; // bnb is 49.01%

	IUniswapV2Router02 public constant PancakeRouter = IUniswapV2Router02(ADDRESS_PANCAKE_ROUTER);
	uint256 public swap_threshold = 50 ether;
	bool public auto_swap = false;
	bool public auto_unpair = false;

	receive() external payable {} // for Etherium Net(payable keyword)

	//---------------------------------------------------------------
	// Front-end connectors
	//---------------------------------------------------------------
	event SetOperatorCB(address indexed operator, address _new_operator);
	event SetValutCB(address indexed operator, address _vault);
	event SetTokenCB(address indexed operator, address _arrow, address _target);
	event SetAssetDistributeRatio(address indexed operator, uint256 _bnd_ratio);
	event SetSwapThresholdCB(address indexed operator,  uint256 _threshold);
	event HandleStuckCB(address indexed operator, address _token,  uint256 _amount, address _to);
	event MakeJuiceCB(address indexed operator);
	event SetAutoSwapCB(address indexed operator, bool _auto_swap);
	event SetAutoUnpairCB(address indexed operator, bool _auto_unpair);

	//---------------------------------------------------------------
	// Modifier
	//---------------------------------------------------------------
	modifier onlyOperator() { require(msg.sender == address_operator, "onlyOperator: Not authorized"); _; }
	
	//---------------------------------------------------------------
	// External Method
	//---------------------------------------------------------------
	constructor(address _address_vault)
	{
		address_operator = msg.sender;
		address_vault = _address_vault;
	}

	function make_juice(address _address_token) external nonReentrant
	{
		require(_address_token != address(0), "make_juice: Invalid token address");

		if(auto_unpair == true && _is_uniswapv2_pair(_address_token) == true)
		{
			IUniswapV2Pair pair = IUniswapV2Pair(_address_token);
			pair.burn(address(this));
			
			_vault_erc20(pair.token0());
			_vault_erc20(pair.token1());

			if(auto_swap == true)
			{
				_squeeze_juice(pair.token0());
				_squeeze_juice(pair.token1());

				_collect_my_busd();
				_collect_my_bnb();
			}
		}
		else
		{
			_vault_erc20(_address_token);

			if(auto_swap == true)
			{
				_squeeze_juice(_address_token);

				_collect_my_busd();
				_collect_my_bnb();
			}
		}
		
		emit MakeJuiceCB(msg.sender);
	}

	//---------------------------------------------------------------
	// Internal Method
	//---------------------------------------------------------------
	function _squeeze_juice(address _native_token) internal
	{
		uint256 amount_token = IERC20(_native_token).balanceOf(address(this));
		if(amount_token < swap_threshold || _native_token == ADDRESS_BUSD || _native_token == ADDRESS_WBNB)
			return;

		uint256 amount_busd = (amount_token * bnb_per_busd_vault_ratio_e6) / 1e6;
		uint256 amount_wbnb  = amount_token - amount_busd;

		_swap_to(_native_token, ADDRESS_BUSD, amount_busd);
		_swap_to(_native_token, ADDRESS_WBNB, amount_wbnb);
	}
	
	function _get_approve_pancake(address _address_token) private
	{
		IERC20 token = IERC20(_address_token);
		
		if(token.allowance(address(this), address(PancakeRouter)) == 0)
			token.safeApprove(address(PancakeRouter), type(uint256).max);
	}

	function _collect_my_busd() internal
	{
		uint256 my_busd_amount = IERC20(ADDRESS_BUSD).balanceOf(address(this));
		IERC20(ADDRESS_BUSD).transfer(address_vault, my_busd_amount);
	}

	function _collect_my_bnb() internal
	{
		// wbnb -> bnb
		uint256 my_wbnb_amount = IERC20(ADDRESS_WBNB).balanceOf(address(this));
		IWETH(ADDRESS_WBNB).withdraw(my_wbnb_amount);
		uint256 my_bnb_amount = address(this).balance;
		payable(address_vault).transfer(my_bnb_amount);
	}
	
	function _swap_to(address _from, address _to, uint256 amount) internal
	{
		address[] memory best_path = _get_best_swap_root(_from, _to, amount);
		PancakeRouter.swapExactTokensForTokens(amount, 0, best_path, address(this), block.timestamp);
	}

	function _get_best_swap_root(address _from, address _to, uint256 _amount) internal view returns(address[] memory)
	{
		if(_to == ADDRESS_WBNB)
		{
			address[] memory swap_path_a = _get_swap_root(_from, _to);
			return swap_path_a;
		}
		else
		{
			address[] memory swap_path_a = _get_swap_root(_from, _to);
			address[] memory swap_path_b = _get_swap_root_though(_from, ADDRESS_WBNB, _to);

			uint256[] memory amount_path_a = PancakeRouter.getAmountsOut(_amount, swap_path_a);
			uint256[] memory amount_path_b = PancakeRouter.getAmountsOut(_amount, swap_path_b);

			if(amount_path_a[amount_path_a.length-1] > amount_path_b[amount_path_b.length-1])
				return swap_path_a;
			else
				return swap_path_b;
		}
	}

	function _get_swap_root(address _from, address _to) internal pure returns(address[] memory)
	{
		address[] memory path = new address[](2);
		path[0] = _from;
		path[1] = _to;
		return path;
	}

	function _get_swap_root_though(address _from, address _way_point, address _to) internal pure returns(address[] memory)
	{
		address[] memory path = new address[](3);
		path[0] = _from;
		path[1] = _way_point;
		path[2] = _to;
		return path;
	}

	// !!! function _is_uniswapv2_pair(address _address_pair) internal view returns(bool)
	function _is_uniswapv2_pair(address _address_pair) public view returns(bool)
	{
		if(_address_pair == address(0)) 
			return false;

		IUniswapV2Factory factory = IUniswapV2Factory(PancakeRouter.factory());
		address wethAddress = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
		address pair = factory.getPair(_address_pair, wethAddress);
		return pair == _address_pair;
	}
	
	// !!!
	function _is_uniswapv2_pair_t2(address _address_pair) public view returns(bool) 
	{
		if(_address_pair == address(0)) 
			return false;

		IUniswapV2Factory factory = IUniswapV2Factory(PancakeRouter.factory());
		address pair = factory.getPair(_address_pair, address(0));
		return pair == _address_pair;
	}

	// !!! function _vault_erc20(address _address_token) internal
	function _vault_erc20(address _address_token) public
	{
		IERC20 token = IERC20(_address_token);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(address_vault, balance);
	}
	
	//---------------------------------------------------------------
	// Getters and Setters
	//---------------------------------------------------------------
	function set_operator(address _new_operator) external onlyOperator
	{
		require(_new_operator != address(0), "set_operator: Wrong address");
		address_operator = _new_operator;
		emit SetOperatorCB(msg.sender, _new_operator);
	}
	
	function set_address_token(address _address_arrow, address _address_target) external onlyOperator
	{
		address_arrow_token = _address_arrow;
		_get_approve_pancake(address_arrow_token);

		address_target_token = _address_target;
		_get_approve_pancake(address_target_token);
		emit SetTokenCB(msg.sender, _address_arrow, _address_target);
	}

	function set_bnb_per_busd_vault_ratio(uint256 _bnd_ratio) external onlyOperator
	{
		bnb_per_busd_vault_ratio_e6 = _bnd_ratio;
		emit SetAssetDistributeRatio(msg.sender, _bnd_ratio);
	}

	function set_swap_threshold(uint256 _threshold) external onlyOperator
	{
		swap_threshold = _threshold;
		emit SetSwapThresholdCB(msg.sender, _threshold);
	}

	function set_auto_swap(bool on) external onlyOperator()
	{
		auto_swap = on;
		emit SetAutoSwapCB(msg.sender, on);
	}

	function set_auto_unpair(bool on) external onlyOperator()
	{
		auto_unpair = on;
		emit SetAutoUnpairCB(msg.sender, on);
	}

	function handle_stuck(address _address_token, uint256 _amount, address _to) external onlyOperator nonReentrant
	{
		IERC20(_address_token).safeTransfer(_to, _amount);
		emit HandleStuckCB(msg.sender, _address_token, _amount, _to);
	}
}

