// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";
import "./AccessControl.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./ECDSA.sol";

import "./IMasterChef.sol";
import "./IMasterChefCallback.sol";
import "./IOreoBoosterConfig.sol";
import "./IWNativeRelayer.sol";
import "./IWETH.sol";
import "./SafeToken.sol";

contract OreoBooster is Ownable, Pausable, ReentrancyGuard, AccessControl, IMasterChefCallback, IERC721Receiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;

  bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
  // keccak256(abi.encodePacked("I am an EOA"))
  bytes32 public constant SIGNATURE_HASH = 0x08367bb0e0d2abf304a79452b2b95f4dc75fda0fc6df55dca6e5ad183de10cf0;

  IMasterChef public masterChef;
  IOreoBoosterConfig public oreoboosterConfig;
  IERC20 public oreo;
  IWNativeRelayer public wNativeRelayer;
  address public wNative;

  struct UserInfo {
    uint256 accumBoostedReward;
    uint256 lastUserActionTime;
  }

  struct NFTStakingInfo {
    address nftAddress;
    uint256 nftTokenId;
  }

  mapping(address => mapping(address => UserInfo)) public userInfo;

  mapping(address => uint256) public totalAccumBoostedReward;
  mapping(address => mapping(address => NFTStakingInfo)) public userStakingNFT;

  uint256 public _IN_EXEC_LOCK;

  uint256 public constant VERSION = 1;

  event StakeNFT(address indexed staker, address indexed stakeToken, address nftAddress, uint256 nftTokenId);
  event UnstakeNFT(address indexed staker, address indexed stakeToken, address nftAddress, uint256 nftTokenId);
  event Stake(address indexed staker, IERC20 indexed stakeToken, uint256 amount);
  event Unstake(address indexed unstaker, IERC20 indexed stakeToken, uint256 amount);
  event Harvest(address indexed harvester, IERC20 indexed stakeToken, uint256 amount);
  event EmergencyWithdraw(address indexed caller, IERC20 indexed stakeToken, uint256 amount);
  event MasterChefCall(
    address indexed user,
    uint256 extraReward,
    address stakeToken,
    uint256 prevEnergy,
    uint256 currentEnergy
  );
  event Pause();
  event Unpause();

  constructor(
    IERC20 _oreo,
    IMasterChef _masterChef,
    IOreoBoosterConfig _oreoboosterConfig,
    IWNativeRelayer _wNativeRelayer,
    address _wNative
  ) public {
    require(_wNative != address(0), "OreoBooster::constructor:: _wNative cannot be address(0)");
    require(address(_oreo) != address(0), "OreoNFTOffering::constructor:: _oreo cannot be address(0)");
    require(address(_masterChef) != address(0), "OreoNFTOffering::constructor:: _masterChef cannot be address(0)");
    require(
      address(_oreoboosterConfig) != address(0),
      "OreoNFTOffering::constructor:: _oreoboosterConfig cannot be address(0)"
    );
    require(
      address(_wNativeRelayer) != address(0),
      "OreoNFTOffering::constructor:: _wNativeRelayer cannot be address(0)"
    );

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(GOVERNANCE_ROLE, _msgSender());

    masterChef = _masterChef;
    oreoboosterConfig = _oreoboosterConfig;
    oreo = _oreo;
    wNativeRelayer = _wNativeRelayer;
    wNative = _wNative;

    _IN_EXEC_LOCK = _NOT_ENTERED;
  }

  /// @dev Ensure that the function is called with the execution scope
  modifier inExec() {
    require(_IN_EXEC_LOCK == _NOT_ENTERED, "OreoBooster::inExec:: in exec lock");
    require(address(masterChef) == _msgSender(), "OreoBooster::inExec:: not from the master chef");
    _IN_EXEC_LOCK = _ENTERED;
    _;
    _IN_EXEC_LOCK = _NOT_ENTERED;
  }

  /// @dev validate whether a specified stake token is allowed
  modifier isStakeTokenOK(address _stakeToken) {
    require(oreoboosterConfig.stakeTokenAllowance(_stakeToken), "OreoBooster::isStakeTokenOK::bad stake token");
    _;
  }

  /// @dev validate whether a specified nft can be staked into a particular staoke token
  modifier isOreoBoosterNftOK(
    address _stakeToken,
    address _nftAddress,
    uint256 _nftTokenId
  ) {
    require(
      oreoboosterConfig.oreoboosterNftAllowance(_stakeToken, _nftAddress, _nftTokenId),
      "OreoBooster::isOreoBoosterNftOK::bad nft"
    );
    _;
  }

  modifier permit(bytes calldata _sig) {
    address recoveredAddress = ECDSA.recover(ECDSA.toEthSignedMessageHash(SIGNATURE_HASH), _sig);
    require(recoveredAddress == _msgSender(), "OreoBooster::permit::INVALID_SIGNATURE");
    _;
  }

  modifier onlyGovernance() {
    require(hasRole(GOVERNANCE_ROLE, _msgSender()), "OreoBooster::onlyGovernance::only GOVERNANCE role");
    _;
  }

  /// @dev Require that the caller must be an EOA account to avoid flash loans.
  modifier onlyEOA() {
    require(msg.sender == tx.origin, "OreoBooster::onlyEOA:: not eoa");
    _;
  }

  /**
   * @notice Triggers stopped state
   * @dev Only possible when contract not paused.
   */
  function pause() external onlyGovernance whenNotPaused {
    _pause();
    emit Pause();
  }

  /**
   * @notice Returns to normal state
   * @dev Only possible when contract is paused.
   */
  function unpause() external onlyGovernance whenPaused {
    _unpause();
    emit Unpause();
  }

  /// @dev View function to see pending booster OREOs on frontend.
  function pendingBoosterOreo(address _stakeToken, address _user) external view returns (uint256) {
    uint256 pendingOreo = masterChef.pendingOreo(_stakeToken, _user);
    NFTStakingInfo memory stakingNFT = userStakingNFT[_stakeToken][_user];
    if (stakingNFT.nftAddress == address(0)) {
      return 0;
    }
    (, , uint256 boostBps) = oreoboosterConfig.energyInfo(stakingNFT.nftAddress, stakingNFT.nftTokenId);
    // if (currentEnergy == 0) {
    //   return 0;
    // }
    return pendingOreo.mul(boostBps).div(1e4);
    // return Math.min(currentEnergy, pendingOreo.mul(boostBps).div(1e4));
  }

  /// @dev Internal function for withdraoreo a boosted stake token and receive a reward from a master chef
  /// @param _stakeToken specified stake token
  /// @param _shares user's shares to be withdrawn
  function _withdrawFromMasterChef(IERC20 _stakeToken, uint256 _shares) internal {
    if (_shares == 0) return;
    if (address(_stakeToken) == address(oreo)) {
      masterChef.withdrawOreo(_msgSender(), _shares);
    } else {
      masterChef.withdraw(_msgSender(), address(_stakeToken), _shares);
    }
  }

  /// @dev Internal function for harvest a reward from a master chef
  /// @param _stakeToken specified stake token
  function _harvestFromMasterChef(address user, IERC20 _stakeToken) internal {
    (uint256 userStakeAmount, , ) = masterChef.userInfo(address(_stakeToken), user);
    if (userStakeAmount == 0) {
      emit Harvest(user, _stakeToken, 0);
      return;
    }
    uint256 beforeReward = oreo.balanceOf(user);
    masterChef.harvest(user, address(_stakeToken));

    emit Harvest(user, _stakeToken, oreo.balanceOf(user).sub(beforeReward));
  }

  /// @notice function for staking a new nft
  /// @dev This one is a preparation for nft staking info, if nft address and nft token id are the same with existing record, it will be reverted
  /// @param _stakeToken a specified stake token address
  /// @param _nftAddress composite key for nft
  /// @param _nftTokenId composite key for nft
  function stakeNFT(
    address _stakeToken,
    address _nftAddress,
    uint256 _nftTokenId
  )
    external
    whenNotPaused
    isStakeTokenOK(_stakeToken)
    isOreoBoosterNftOK(_stakeToken, _nftAddress, _nftTokenId)
    nonReentrant
    onlyEOA
  {
    _stakeNFT(_stakeToken, _nftAddress, _nftTokenId);
  }

  /// @dev avoid stack-too-deep by branching the function
  function _stakeNFT(
    address _stakeToken,
    address _nftAddress,
    uint256 _nftTokenId
  ) internal {
    NFTStakingInfo memory toBeSentBackNft = userStakingNFT[_stakeToken][_msgSender()];
    require(
      toBeSentBackNft.nftAddress != _nftAddress || toBeSentBackNft.nftTokenId != _nftTokenId,
      "OreoBooster::stakeNFT:: nft already staked"
    );
    _harvestFromMasterChef(_msgSender(), IERC20(_stakeToken));

    userStakingNFT[_stakeToken][_msgSender()] = NFTStakingInfo({ nftAddress: _nftAddress, nftTokenId: _nftTokenId });

    IERC721(_nftAddress).safeTransferFrom(_msgSender(), address(this), _nftTokenId);

    if (toBeSentBackNft.nftAddress != address(0)) {
      IERC721(toBeSentBackNft.nftAddress).safeTransferFrom(address(this), _msgSender(), toBeSentBackNft.nftTokenId);
    }
    emit StakeNFT(_msgSender(), _stakeToken, _nftAddress, _nftTokenId);
  }

  /// @notice function for unstaking a current nft
  /// @dev This one is a preparation for nft staking info, if nft address and nft token id are the same with existing record, it will be reverted
  /// @param _stakeToken a specified stake token address
  function unstakeNFT(address _stakeToken) external isStakeTokenOK(_stakeToken) nonReentrant onlyEOA {
    _unstakeNFT(_stakeToken);
  }

  /// @dev avoid stack-too-deep by branching the function
  function _unstakeNFT(address _stakeToken) internal {
    NFTStakingInfo memory toBeSentBackNft = userStakingNFT[_stakeToken][_msgSender()];
    require(toBeSentBackNft.nftAddress != address(0), "OreoBooster::stakeNFT:: no nft staked");

    _harvestFromMasterChef(_msgSender(), IERC20(_stakeToken));

    userStakingNFT[_stakeToken][_msgSender()] = NFTStakingInfo({ nftAddress: address(0), nftTokenId: 0 });

    IERC721(toBeSentBackNft.nftAddress).safeTransferFrom(address(this), _msgSender(), toBeSentBackNft.nftTokenId);

    emit UnstakeNFT(_msgSender(), _stakeToken, toBeSentBackNft.nftAddress, toBeSentBackNft.nftTokenId);
  }

  /// @notice for staking a stakeToken and receive some rewards
  /// @param _stakeToken a specified stake token to be staked
  /// @param _amount amount to stake
  function stake(IERC20 _stakeToken, uint256 _amount)
    external
    payable
    whenNotPaused
    isStakeTokenOK(address(_stakeToken))
    nonReentrant
  {
    require(_amount > 0, "OreoBooster::stake::nothing to stake");

    UserInfo storage user = userInfo[address(_stakeToken)][_msgSender()];

    _harvestFromMasterChef(_msgSender(), _stakeToken);
    user.lastUserActionTime = block.timestamp;
    _stakeToken.safeApprove(address(masterChef), _amount);
    _safeWrap(_stakeToken, _amount);

    if (address(_stakeToken) == address(oreo)) {
      masterChef.depositOreo(_msgSender(), _amount);
    } else {
      masterChef.deposit(_msgSender(), address(_stakeToken), _amount);
    }

    _stakeToken.safeApprove(address(masterChef), 0);

    emit Stake(_msgSender(), _stakeToken, _amount);
  }

  /// @dev internal function for unstaking a stakeToken and receive some rewards
  /// @param _stakeToken a specified stake token to be unstaked
  /// @param _amount amount to stake
  function _unstake(IERC20 _stakeToken, uint256 _amount) internal {
    require(_amount > 0, "OreoBooster::_unstake::use harvest instead");

    UserInfo storage user = userInfo[address(_stakeToken)][_msgSender()];

    _withdrawFromMasterChef(_stakeToken, _amount);

    user.lastUserActionTime = block.timestamp;
    _safeUnwrap(_stakeToken, _msgSender(), _amount);

    emit Unstake(_msgSender(), _stakeToken, _amount);
  }

  /// @dev function for unstaking a stakeToken and receive some rewards
  /// @param _stakeToken a specified stake token to be unstaked
  /// @param _amount amount to stake
  function unstake(address _stakeToken, uint256 _amount) external isStakeTokenOK(_stakeToken) nonReentrant {
    _unstake(IERC20(_stakeToken), _amount);
  }

  /// @notice function for unstaking all portion of stakeToken and receive some rewards
  /// @dev similar to unstake with user's shares
  /// @param _stakeToken a specified stake token to be unstaked
  function unstakeAll(address _stakeToken) external isStakeTokenOK(_stakeToken) nonReentrant {
    (uint256 userStakeAmount, , ) = masterChef.userInfo(address(_stakeToken), _msgSender());
    _unstake(IERC20(_stakeToken), userStakeAmount);
  }

  /// @notice function for harvesting the reward
  /// @param _stakeToken a specified stake token to be harvested
  function harvest(address _stakeToken) external whenNotPaused isStakeTokenOK(_stakeToken) nonReentrant {
    _harvestFromMasterChef(_msgSender(), IERC20(_stakeToken));
  }

  /// @notice function for harvesting rewards in specified staking tokens
  /// @param _stakeTokens specified stake tokens to be harvested
  function harvest(address[] calldata _stakeTokens) external whenNotPaused nonReentrant {
    for (uint256 i = 0; i < _stakeTokens.length; i++) {
      require(oreoboosterConfig.stakeTokenAllowance(_stakeTokens[i]), "OreoBooster::harvest::bad stake token");
      _harvestFromMasterChef(_msgSender(), IERC20(_stakeTokens[i]));
    }
  }

  /// @dev a notifier function for letting some observer call when some conditions met
  /// @dev currently, the caller will be a master chef calling before a oreo lock
  function masterChefCall(
    address stakeToken,
    address userAddr,
    uint256 unboostedReward
  ) external override inExec {
    NFTStakingInfo memory stakingNFT = userStakingNFT[stakeToken][userAddr];
    UserInfo storage user = userInfo[stakeToken][userAddr];
    if (stakingNFT.nftAddress == address(0)) {
      return;
    }
    (, uint256 currentEnergy, uint256 boostBps) = oreoboosterConfig.energyInfo(
      stakingNFT.nftAddress,
      stakingNFT.nftTokenId
    );
    // if (currentEnergy == 0) {
    //   return;
    // }
    uint256 extraReward = unboostedReward.mul(boostBps).div(1e4);
    totalAccumBoostedReward[stakeToken] = totalAccumBoostedReward[stakeToken].add(extraReward);
    user.accumBoostedReward = user.accumBoostedReward.add(extraReward);
    uint256 newEnergy = 0;
    masterChef.mintExtraReward(stakeToken, userAddr, extraReward);
    // oreoboosterConfig.consumeEnergy(stakingNFT.nftAddress, stakingNFT.nftTokenId, extraReward);

    emit MasterChefCall(userAddr, extraReward, stakeToken, currentEnergy, newEnergy);
  }

  function _safeWrap(IERC20 _quoteBep20, uint256 _amount) internal {
    if (msg.value != 0) {
      require(address(_quoteBep20) == wNative, "OreoBooster::_safeWrap:: baseToken is not wNative");
      require(_amount == msg.value, "OreoBooster::_safeWrap:: value != msg.value");
      IWETH(wNative).deposit{ value: msg.value }();
      return;
    }
    _quoteBep20.safeTransferFrom(_msgSender(), address(this), _amount);
  }

  function _safeUnwrap(
    IERC20 _quoteBep20,
    address _to,
    uint256 _amount
  ) internal {
    if (address(_quoteBep20) == wNative) {
      _quoteBep20.safeTransfer(address(wNativeRelayer), _amount);
      wNativeRelayer.withdraw(_amount);
      SafeToken.safeTransferETH(_to, _amount);
      return;
    }
    _quoteBep20.safeTransfer(_to, _amount);
  }

  /**
   * @notice Withdraws a stake token from MasterChef back to the user considerless the rewards.
   * @dev EMERGENCY ONLY
   */
  function emergencyWithdraw(IERC20 _stakeToken) external isStakeTokenOK(address(_stakeToken)) {
    UserInfo storage user = userInfo[address(_stakeToken)][_msgSender()];
    (uint256 userStakeAmount, , ) = masterChef.userInfo(address(_stakeToken), _msgSender());

    user.lastUserActionTime = block.timestamp;
    masterChef.emergencyWithdraw(_msgSender(), address(_stakeToken));

    emit EmergencyWithdraw(_msgSender(), _stakeToken, userStakeAmount);
  }

  /// @dev when doing a safeTransferFrom, the caller needs to implement this, for safety reason
  function onERC721Received(
    address, /*operator*/
    address, /*from*/
    uint256, /*tokenId*/
    bytes calldata /*data*/
  ) external override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

  /// @dev Fallback function to accept ETH. Workers will send ETH back the pool.
  receive() external payable {}
}

