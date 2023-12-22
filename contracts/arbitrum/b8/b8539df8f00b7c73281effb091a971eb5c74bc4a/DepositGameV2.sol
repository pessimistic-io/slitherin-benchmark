// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IEggs.sol";

contract DepositGameV2 is Ownable {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	bool public gameOver = false;
	bool public startEnable = false;

	uint256 public winerIndex;
	uint256 public startTime;

	address public treasury;
	address public USDC;

	uint public rewardUsdc;
	address[] public rewardTokens;
	address[] public tokenList;
	IUniswapV2Pair[] public lpList;

	mapping(uint256 => bool) public opened;
	mapping(address => bool) public isSupportToken;
	mapping(address => PoolInfo) public poolInfos;
	mapping(address => bool) public withdrawEnabled;
	mapping(address => bool) operators;

	struct PoolInfo {
		bool enable;
		IEggsToken rewardToken;
		IERC20 stakeToken;
		uint256 totalSupply;
		uint256 reserve;
		uint256 canMintAmount;
		uint256 rewardLastStored;
		mapping(address => uint256) userRewardStored;
		mapping(address => uint256) newReward;
		mapping(address => uint256) claimedReward;
		mapping(address => uint256) balanceOf;
	}

	event AddPool(address indexed token, address indexed stakeToken);
	event Staked(address indexed token, address indexed user, uint256 amount);
	event Withdrawn(address indexed token, address indexed user, uint256 amount);
	event RewardPaid(address indexed user, address indexed token, uint256 reward);
	event SetStartTime(uint256 indexed startTime);

	constructor(address[] memory _rewardTokens, address[] memory _stakeTokens, address usdc, address _treasury) {
		for (uint256 i = 0; i != _rewardTokens.length; i++) {
			addPool(_rewardTokens[i], _stakeTokens[i]);
		}
		USDC = usdc;
		treasury = _treasury;
	}

	modifier isStart() {
		require(startEnable, "not start");
		require(startTime > 0 && startTime <= block.timestamp, "not start");
		_;
	}

	modifier isGameOver() {
		require(!gameOver, "game over");
		_;
	}

	modifier isOprator() {
		require(!operators[msg.sender], "not oprater");
		_;
	}

	function setStartTime(uint256 _startTime) external onlyOwner {
		startTime = _startTime;
		startEnable = true;
		emit SetStartTime(_startTime);
	}

	function setOperator(address _operator) external onlyOwner {
		operators[_operator] = true;
	}

	modifier updateDispatch() {
		for (uint256 i = 0; i != rewardTokens.length; i++) {
			address token = rewardTokens[i];
			PoolInfo storage pool = poolInfos[token];
			if (pool.enable) {
				pool.rewardLastStored = rewardPer(pool);
				if (pool.rewardLastStored > 0) {
					uint256 balance = pool.canMintAmount;
					pool.reserve = balance;
					if (msg.sender != address(0)) {
						pool.newReward[msg.sender] = available(token, msg.sender);
						pool.userRewardStored[msg.sender] = pool.rewardLastStored;
					}
				}
			}
		}
		_;
	}

	function setTreasury(address _treasury) external onlyOwner {
		treasury = _treasury;
	}

	function setIsSupportToken(address token, bool enable) external onlyOwner {
		isSupportToken[token] = enable;
	}

	function addPool(address rewardToken, address stakeToken) public onlyOwner {
		require(address(poolInfos[rewardToken].rewardToken) == address(0), "pool is exits");
		poolInfos[rewardToken].rewardToken = IEggsToken(rewardToken);
		poolInfos[rewardToken].stakeToken = IERC20(stakeToken);
		poolInfos[rewardToken].enable = true;
		rewardTokens.push(rewardToken);
		lpList.push(IUniswapV2Pair(stakeToken));
		isSupportToken[rewardToken] = true;
		emit AddPool(rewardToken, stakeToken);
	}

	function enablePool(address token, bool enable) external onlyOwner {
		require(address(poolInfos[token].rewardToken) != address(0), "pool not is exits");
		poolInfos[token].rewardToken = IEggsToken(token);
		poolInfos[token].enable = enable;
	}

	function getAllSupplyTokens() public view returns (address[] memory) {
		return rewardTokens;
	}

	function claimedReward(address token, address account) public view returns (uint256) {
		PoolInfo storage pool = poolInfos[token];
		return pool.claimedReward[account];
	}

	function totalSupply(address token) public view returns (uint256) {
		return poolInfos[token].totalSupply;
	}

	function balanceOf(address token, address account) public view returns (uint256) {
		require(address(poolInfos[token].rewardToken) != address(0), "pool not is exits");
		return poolInfos[token].balanceOf[account];
	}

	function lastReward(PoolInfo storage pool) private view returns (uint256) {
		if (pool.totalSupply == 0) {
			return 0;
		}
		uint256 balance = pool.canMintAmount;
		return balance.sub(pool.reserve);
	}

	function rewardPer(PoolInfo storage pool) private view returns (uint256) {
		if (pool.totalSupply == 0) {
			return pool.rewardLastStored;
		}
		return pool.rewardLastStored.add(lastReward(pool).mul(1e18).div(pool.totalSupply));
	}

	function available(address token, address account) public view returns (uint256) {
		PoolInfo storage pool = poolInfos[token];
		uint256 balance = pool.balanceOf[account];
		return balance.mul(rewardPer(pool).sub(pool.userRewardStored[account])).div(1e18).add(pool.newReward[account]);
	}

	function stake(address token, uint256 amount) external isStart isGameOver updateDispatch {
		require(isSupportToken[token], "not support token");
		require(amount > 0, "invalid amount");
		getStage();

		PoolInfo storage pool = poolInfos[token];
		pool.stakeToken.safeTransferFrom(msg.sender, address(this), amount);
		pool.totalSupply = pool.totalSupply.add(amount);
		pool.balanceOf[msg.sender] = pool.balanceOf[msg.sender].add(amount);
		emit Staked(address(pool.stakeToken), msg.sender, amount);
	}

	function withdraw(address token, uint256 amount) external isStart isGameOver updateDispatch {
		require(isSupportToken[token], "not support token");
		require(amount > 0, "invalid amount");
		getStage();
		require(withdrawEnabled[token], "can not withdraw");
		PoolInfo storage pool = poolInfos[token];
		if (amount > pool.balanceOf[msg.sender]) {
			amount = pool.balanceOf[msg.sender];
		}
		pool.totalSupply = pool.totalSupply.sub(amount);
		pool.balanceOf[msg.sender] = pool.balanceOf[msg.sender].sub(amount);
		pool.stakeToken.safeTransfer(msg.sender, amount);
		emit Withdrawn(address(pool.stakeToken), msg.sender, amount);
	}

	function claim(address token) external updateDispatch {
		PoolInfo storage pool = poolInfos[token];
		uint256 reward = available(token, msg.sender);
		if (reward <= 0) {
			return;
		}
		pool.reserve = pool.reserve.sub(reward);
		pool.newReward[msg.sender] = 0;

		pool.claimedReward[msg.sender] = pool.claimedReward[msg.sender].add(reward);
		pool.canMintAmount = pool.canMintAmount.sub(reward);

		pool.rewardToken.mint(msg.sender, reward);

		emit RewardPaid(msg.sender, token, reward);
	}

	function withdrawToken(address _token, uint256 amount) external onlyOwner {
		IERC20 token = IERC20(_token);
		token.transfer(msg.sender, amount);
	}

	function updateMintAmount(uint256 amount) external {
		require(isSupportToken[msg.sender], "not support token");
		PoolInfo storage pool = poolInfos[msg.sender];
		pool.canMintAmount = pool.canMintAmount + amount;
	}

	function handleComparePool() public view returns (uint256) {
		uint256 maxUsdcReserve;
		uint256 winTokenIndex;
		for (uint256 i = 0; i <= 2; i++) {
			IUniswapV2Pair _token = lpList[i];
			(uint112 _reserve0, uint112 _reserve1, ) = _token.getReserves();
			address token0 = _token.token0();
			uint112 usdcReserve = token0 == USDC ? _reserve0 : _reserve1;
			uint _tokenBalance = _token.balanceOf(address(this)) * 1e18;
			uint _totalSupply = _token.totalSupply();
			if (_totalSupply == 0) continue;
			uint _rate = _tokenBalance.div(_totalSupply);
			uint thisUsdcReserve = (usdcReserve * _rate) / 1e18;

			if (thisUsdcReserve > maxUsdcReserve) {
				maxUsdcReserve = thisUsdcReserve;
				winTokenIndex = i;
			}
		}
		return winTokenIndex;
	}

	function handleGameOver(uint256 _winerIndex) internal {
		require(gameOver, "game not over");
		require(_winerIndex < lpList.length, "tokenIndex error");

		for (uint256 i = 0; i <= 2; i++) {
			if (i != _winerIndex) {
				//withdraw lp
				IUniswapV2Pair failLp = lpList[i];
				uint failBalance = failLp.balanceOf(address(this));
				if (failBalance > 0) {
					failLp.transfer(address(failLp), failLp.balanceOf(address(this)));
					failLp.burn(address(this));
				}
			}
		}

		IERC20 u = IERC20(USDC);
		rewardUsdc = u.balanceOf(address(this));
		u.safeTransfer(treasury, rewardUsdc);
	}

	function getStage() public isStart {
		uint256 timeDelta = block.timestamp - startTime;
		if (
			timeDelta < 4 days ||
			(timeDelta > 5 days && timeDelta < 8 days) ||
			(timeDelta > 9 days && timeDelta < 12 days) ||
			(timeDelta > 13 days && timeDelta < 14 days)
		) {
			for (uint256 i = 0; i <= 2; i++) {
				if (withdrawEnabled[rewardTokens[i]]) {
					withdrawEnabled[rewardTokens[i]] = false;
				}
			}
		} else if ((timeDelta >= 4 days && timeDelta <= 5 days)) {
			if (opened[1]) {
				return;
			}
			for (uint256 i = 0; i <= 2; i++) {
				if (withdrawEnabled[rewardTokens[i]]) {
					withdrawEnabled[rewardTokens[i]] = false;
				}
			}
			uint256 _tokenIndex = handleComparePool();
			withdrawEnabled[rewardTokens[_tokenIndex]] = true;
			opened[1] = true;
		} else if ((timeDelta >= 8 days && timeDelta <= 9 days)) {
			if (opened[2]) {
				return;
			}
			for (uint256 i = 0; i <= 2; i++) {
				if (withdrawEnabled[rewardTokens[i]]) {
					withdrawEnabled[rewardTokens[i]] = false;
				}
			}
			uint256 _tokenIndex = handleComparePool();
			withdrawEnabled[rewardTokens[_tokenIndex]] = true;
			opened[2] = true;
		} else if ((timeDelta >= 12 days && timeDelta <= 13 days)) {
			if (opened[3]) {
				return;
			}
			for (uint256 i = 0; i <= 2; i++) {
				if (withdrawEnabled[rewardTokens[i]]) {
					withdrawEnabled[rewardTokens[i]] = false;
				}
			}
			uint256 _tokenIndex = handleComparePool();
			withdrawEnabled[rewardTokens[_tokenIndex]] = true;
			opened[3] = true;
		} else if ((timeDelta > 14 days)) {
			if (gameOver) {
				return;
			}
			for (uint256 i = 0; i <= 2; i++) {
				if (withdrawEnabled[rewardTokens[i]]) {
					withdrawEnabled[rewardTokens[i]] = false;
				}
			}
			uint256 _tokenIndex = handleComparePool();
			withdrawEnabled[rewardTokens[_tokenIndex]] = true;
			gameOver = true;
			handleGameOver(_tokenIndex);
			winerIndex = _tokenIndex;
		}
	}

	function getStageStatus() public view returns (bool[3] memory) {
		bool[3] memory status;
		uint256 timeDelta = block.timestamp - startTime;
		if (!startEnable) {
			return status;
		}

		if (startTime == 0 || startTime > block.timestamp) {
			return status;
		}

		if (
			timeDelta < 4 days ||
			(timeDelta > 5 days && timeDelta < 8 days) ||
			(timeDelta > 9 days && timeDelta < 12 days) ||
			(timeDelta > 13 days && timeDelta < 14 days)
		) {
			for (uint256 i = 0; i <= 2; i++) {
				if (status[i]) {
					status[i] = false;
				}
			}
		} else if ((timeDelta >= 4 days && timeDelta <= 5 days)) {
			if (opened[1]) {
				for (uint256 i = 0; i <= 2; i++) {
					if (withdrawEnabled[rewardTokens[i]]) {
						status[i] = withdrawEnabled[rewardTokens[i]];
					}
				}
			} else {
				uint256 _tokenIndex = handleComparePool();
				status[_tokenIndex] = true;
			}
		} else if ((timeDelta >= 8 days && timeDelta <= 9 days)) {
			if (opened[2]) {
				for (uint256 i = 0; i <= 2; i++) {
					if (withdrawEnabled[rewardTokens[i]]) {
						status[i] = withdrawEnabled[rewardTokens[i]];
					}
				}
			} else {
				uint256 _tokenIndex = handleComparePool();
				status[_tokenIndex] = true;
			}
		} else if ((timeDelta >= 12 days && timeDelta <= 13 days)) {
			if (opened[3]) {
				for (uint256 i = 0; i <= 2; i++) {
					if (withdrawEnabled[rewardTokens[i]]) {
						status[i] = withdrawEnabled[rewardTokens[i]];
					}
				}
			} else {
				uint256 _tokenIndex = handleComparePool();
				status[_tokenIndex] = true;
			}
		} else if ((timeDelta > 14 days)) {
			if (gameOver) {
				for (uint256 i = 0; i <= 2; i++) {
					if (withdrawEnabled[rewardTokens[i]]) {
						status[i] = withdrawEnabled[rewardTokens[i]];
					}
				}
			} else {
				uint256 _tokenIndex = handleComparePool();
				status[_tokenIndex] = true;
			}
		}
		return status;
	}

	function getPoolUserInfo(address token, address account) public view returns (uint, uint, uint, uint) {
		PoolInfo storage pool = poolInfos[token];
		if (gameOver) {
			if (!withdrawEnabled[token]) {
				return (0, pool.userRewardStored[account], pool.newReward[account], pool.claimedReward[account]);
			}
		}
		return (pool.balanceOf[account], pool.userRewardStored[account], pool.newReward[account], pool.claimedReward[account]);
	}

	function rebaseTokens() public isOprator {
		for (uint256 i = 0; i != rewardTokens.length; i++) {
			IEggsToken(rewardTokens[i]).rebase();
		}
	}
}

