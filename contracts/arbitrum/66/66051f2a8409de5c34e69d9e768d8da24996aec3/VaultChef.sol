// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IWETH.sol";
import "./IERC721Enumerable.sol";
import "./EnumerableSet.sol";
import "./WETHelper.sol";

interface IVault {
  function deposit(uint _amount, address[] memory _path) external returns(uint256); 
  function withdraw(uint256 _shares, address[] memory _path) external;
}



// MasterChef is the master of Sushi. He can make Sushi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SUSHI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract VaultChef is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  using EnumerableSet for EnumerableSet.UintSet;

  // Info of each user.
  struct UserInfo {
    uint256 amount;   // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.

  //
  // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
  // entitled to a user but is pending to be distributed is:
  //
  //   pending reward = (user.amount * pool.accSushiPerShare) - user.rewardDebt
  //
  // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
  //   1. The pool's `accSushiPerShare` (and `lastRewardTime`) gets updated.
  //   2. User receives the pending reward sent to his/her address.
  //   3. User's `amount` gets updated.
  //   4. User's `rewardDebt` gets updated.
  }
  struct UserInfoSet {
    EnumerableSet.UintSet holderTokens;
  }

  // Info of each pool.
  struct PoolInfo {
    IERC20 lpToken;   // Address of LP token contract.
    uint256 allocPoint;   // How many allocation points assigned to this pool. SUSHIs to distribute per block.
    uint256 amount;   // User deposit amount
    uint256 withdrawFee;  // User withdraw fee
    uint256 lastRewardTime;  // Last block number that SUSHIs distribution occurs.
    uint256 accSushiPerShare; // Accumulated SUSHIs per share, times 1e12. See below.
    IVault vault;
  }

  address public WETH;
  // The SUSHI TOKEN!
  IERC20 public sushi;
  // Dev address.
  address public devaddr;
  // SUSHI tokens created per block.
  uint256 public sushiPerSec;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping (uint256 => mapping (address => UserInfo)) public userInfo;
  mapping (uint256 => mapping (address => UserInfoSet)) private userInfoSet;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;
  // Total allocation poitns. Must be the sum of all allocation points in nft pools.
  uint256 public totalNftAllocPoint = 0;
  // NFT point  for nft count share reward
  uint256 public nftShareAllocPoint = 0;
  // The block number when SUSHI mining starts.
  uint256 public startTime;
  // The last output deacy time.
  uint256 public lastDeacyTime;
  // Current output should devided by decayDivisor.
  uint256 public decayDivisor;
  // ETH Helper for the transfer, stateless.
  WETHelper public wethelper;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 buybackAmount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 buybackAmount);
  event DepositNFT(address indexed user, uint256 indexed pid, uint256 amount);
  event WithdrawNFT(address indexed user, uint256 indexed pid, uint256 amount);
  event Mint(address indexed to, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  function initialize(
    IERC20 _sushi,
    address _devaddr,
    address _weth,
    uint256 _sushiPerSec,
    uint256 _startTime
    ) public initializer {
      Ownable.__Ownable_init();
      sushi = _sushi;
      devaddr = _devaddr;
      WETH = _weth;
      sushiPerSec = _sushiPerSec;  
      startTime = _startTime;
      lastDeacyTime = _startTime;
      decayDivisor = 1;
      wethelper = new WETHelper();
  }

  receive() external payable {
    assert(msg.sender == WETH);
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Add a new lp to the pool. Can only be called by the owner.
  // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(uint256 _allocPoint, address _lpToken, bool _withUpdate, uint256 _withdrawFee, IVault _vault) public {
    require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
    if (_withUpdate) {
      massUpdatePools();
    }
    uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(PoolInfo({
      lpToken: IERC20(_lpToken),
      allocPoint: _allocPoint,
      amount: 0,
      withdrawFee: _withdrawFee,
      lastRewardTime: lastRewardTime,
      accSushiPerShare: 0,
      vault: _vault
    }));
  }

  // Update the given pool's SUSHI allocation point. Can only be called by the owner.
  function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate, uint256 _withdrawFee, uint256 _minAmount) public {
    require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = _allocPoint;
    poolInfo[_pid].withdrawFee = _withdrawFee;
  }
  function setStartBlock(uint256 _startTime) public {
    require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
    startTime = _startTime;
  }
  function setPerBlock(uint256 _sushiPerSec) public {
    require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
    sushiPerSec = _sushiPerSec;
  }
  function setSushi(IERC20 _sushi) external {
    require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
    sushi = _sushi;
  }

  // Return reward multiplier over the given _from to _to time.
  function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
    return _to.sub(_from);
  }

  // View function to see pending SUSHIs on frontend.
  function pendingSushi(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accSushiPerShare = pool.accSushiPerShare;
    uint256 lpSupply = pool.amount;
    // If nft   use   the nftallocpoint / totalNftAllocPoint * poolallocPoint.
    uint256 poolAllcPoint = pool.allocPoint;
    if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp).div(decayDivisor);
      uint256 sushiReward = multiplier.mul(sushiPerSec).mul(poolAllcPoint).div(totalAllocPoint);
      accSushiPerShare = accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
    }
    uint256 pending = user.amount.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
    if (user.amount > 0) return pending;
    return 0;
  }

  // Update reward variables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // Update reward variables of the given pool to be up-to-date.
  // Must  update  pool  in  30days 
  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.timestamp <= pool.lastRewardTime) {
        return;
    }
    if (block.timestamp >= lastDeacyTime.add(30 days)) {
      decayDivisor = decayDivisor.mul(2);
      lastDeacyTime = lastDeacyTime.add(30 days);
    }
    uint256 lpSupply = pool.amount;
    if (lpSupply == 0) {
        pool.lastRewardTime = block.timestamp;
        return;
    }
    uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp).div(decayDivisor);
    uint256 sushiReward = multiplier.mul(sushiPerSec).mul(pool.allocPoint).div(totalAllocPoint);

    mint(address(this), sushiReward);
    pool.accSushiPerShare = pool.accSushiPerShare.add(sushiReward.mul(1e12).div(lpSupply));
    pool.lastRewardTime = block.timestamp;
  }

  function _harvest(PoolInfo storage pool, UserInfo storage user) internal {
    if (user.amount > 0) {
      uint256 pending = user.amount.mul(pool.accSushiPerShare).div(1e12).sub(user.rewardDebt);
      if(pending > 0) {
        safeSushiTransfer(msg.sender, pending);
      }
    }


  }

  // Deposit LP tokens to MasterChef for SUSHI allocation.
  function deposit(uint256 _pid, uint256 _amount, address[] memory _path) public payable {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    _harvest(pool, user);
    if(msg.value != 0) {
      IWETH(WETH).deposit{value: msg.value}();
      IERC20(WETH).safeTransfer(address(pool.vault), msg.value);
    }
    _amount = pool.vault.deposit(_amount, _path);

    if(_amount > 0) {
        pool.amount = pool.amount.add(_amount);
        user.amount = user.amount.add(_amount);
    }

    user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
    emit Deposit(msg.sender, _pid, _amount, 0);
  }

  // Withdraw LP tokens from MasterChef.
  function withdraw(uint256 _pid, uint256 _share, address[] memory _path) public payable {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _share, "!withdraw");

    updatePool(_pid);
    _harvest(pool, user);
 
    uint256 buybackAmount;
    pool.vault.withdraw(_share, _path);
    if(_share > 0) {
      user.amount = user.amount.sub(_share);
      pool.amount = pool.amount.sub(_share);
    }
    user.rewardDebt = user.amount.mul(pool.accSushiPerShare).div(1e12);
    emit Withdraw(msg.sender, _pid, _share, buybackAmount);
  }

  // Safe sushi transfer function, just in case if rounding error causes pool to not have enough SUSHIs.
  // Safe bone transfer function, just in case if rounding error causes pool to not have enough BONEs.
  function safeSushiTransfer(address _to, uint256 _amount) internal {
    uint256 sushiBal = sushi.balanceOf(address(this));
    if (_amount > sushiBal) {
        sushi.transfer(_to, sushiBal);
    } else {
        sushi.transfer(_to, _amount);
    }
  }

  // Update dev address by the previous dev.
  function dev(address _devaddr) public {
    require(msg.sender == devaddr, "dev: wut?");
    devaddr = _devaddr;
  }


  function withdrawEth(address _to, uint256 _amount, bool _isWeth) internal {
    if (_isWeth) {
      IERC20(WETH).safeTransfer(_to, _amount);
    } else {
      IERC20(WETH).safeTransfer(address(wethelper), _amount);
      wethelper.withdraw(WETH, _to, _amount);
    }
  }
  
  function mint(address to, uint256 rewardAmount) internal {
    if (rewardAmount == 0) {
      emit Mint(to, 0);
      return;
    }
    emit Mint(to, rewardAmount);
  }

  function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external pure returns (bytes4){
    operator;
    from;
    tokenId;
    data;
    bytes4 received = 0x150b7a02;
    return received;
  }
}

