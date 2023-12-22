// SPDX-License-Identifier: BUSL-1.1

import "./AbstractERC20Stakeable.sol";
import "./AbstractPool.sol";
import "./AbstractRegistry.sol";
import "./ISwapRouter.sol";
import "./ERC20Fixed.sol";
import "./Errors.sol";
import "./FixedPoint.sol";
import "./Allowlistable.sol";
import "./ERC20.sol";
import "./ERC20PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Counters.sol";
import "./SafeCast.sol";

pragma solidity ^0.8.17;

contract LiquidityPool is
  AbstractPool,
  ERC20PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  AbstractERC20Stakeable,
  Allowlistable
{
  using FixedPoint for uint256;
  using SafeCast for uint256;
  using ERC20Fixed for ERC20PausableUpgradeable;
  using ERC20Fixed for ERC20;
  using Counters for Counters.Counter;

  struct BurnRequest {
    address requestor;
    uint64 requestBlock;
    uint64 burnBlock;
    uint64 expiryBlock;
    uint256 amount;
    uint256 salt;
  }

  ISwapRouter public swapRouter; //settable

  // constant, subject to governance
  uint256 public mintFee;
  uint256 public burnFee;

  // variable
  uint256 public accruedFee;

  bool public transferrable;

  mapping(address => bool) public approvedToken;

  bool public burnRequestOn;
  uint16 public graceBlocks;
  uint16 public requestExpireBlocks;
  Counters.Counter internal _burnRequestCounter;
  mapping(bytes32 => BurnRequest) internal _burnRequests;

  event SetSwapRouterEvent(ISwapRouter swapRouter);
  event CollectAccruedFeeEvent(uint256 accruedFee);
  event SetMintFeeEvent(uint256 mintFee);
  event SetBurnFeeEvent(uint256 burnFee);
  event SetTransferrableEvent(bool transferrable);
  event SetApprovedTokenEvent(address token, bool approved);
  event MintEvent(
    address sender,
    address receiver,
    uint256 baseAmountIn,
    uint256 mintBalance,
    uint256 poolBaseBalance
  );
  event BurnEvent(
    address sender,
    uint256 burnAmountIn,
    uint256 returnBaseBalance,
    uint256 poolBaseBalance
  );
  event SetGraceBlocksEvent(uint16 graceBlocks);
  event SetRequestExpiryBlocksEvent(uint16 requestExpiryBlocks);
  event BurnRequestEvent(
    address requester,
    address holder,
    bytes32 requestHash,
    BurnRequest request
  );
  event SetBurnRequestOn(bool burnRequestOn);
  event AmendBalanceBaseByStakerEvent(
    address user,
    address rewardToken,
    uint256 oldBase,
    uint256 newBase
  );

  function initialize(
    address _owner,
    string memory _name,
    string memory _symbol,
    ERC20 _baseToken,
    AbstractRegistry _registry,
    ISwapRouter _swapRouter
  ) public initializer {
    __ERC20_init(_name, _symbol);
    __ERC20Pausable_init();
    __AbstractPool_init(_owner, _baseToken, _registry);
    __AbstractERC20Stakeable_init();
    __ReentrancyGuard_init();

    swapRouter = _swapRouter;
    mintFee = 0;
    burnFee = 0;
    accruedFee = 0;
    transferrable = true;
    burnRequestOn = false;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier canTransfer() {
    _require(transferrable, Errors.TRANSFER_NOT_ALLOWED);
    _;
  }

  modifier notContract() {
    require(tx.origin == msg.sender);
    _;
  }

  // governance functions

  function setBurnRequestOn(bool _burnRequestOn) external onlyOwner {
    burnRequestOn = _burnRequestOn;
    emit SetBurnRequestOn(burnRequestOn);
  }

  function setGraceBlocks(uint16 _graceBlocks) external onlyOwner {
    graceBlocks = _graceBlocks;
    emit SetGraceBlocksEvent(graceBlocks);
  }

  function setRequestExpiryBlocks(
    uint16 _requestExpiryBlocks
  ) external onlyOwner {
    requestExpireBlocks = _requestExpiryBlocks;
    emit SetRequestExpiryBlocksEvent(requestExpireBlocks);
  }

  function onAllowlist() external onlyOwner {
    _onAllowlist();
  }

  function offAllowlist() external onlyOwner {
    _offAllowlist();
  }

  function addAllowlist(address[] memory _allowed) external onlyOwner {
    _addAllowlist(_allowed);
  }

  function removeAllowlist(address[] memory _removed) external onlyOwner {
    _removeAllowlist(_removed);
  }

  function approveToken(address token, bool approved) external onlyOwner {
    approvedToken[token] = approved;
    emit SetApprovedTokenEvent(token, approved);
  }

  function pauseStaking() external onlyOwner {
    _pauseStaking();
  }

  function unpauseStaking() external onlyOwner {
    _unpauseStaking();
  }

  function setTransferrable(bool _transferrable) external onlyOwner {
    transferrable = _transferrable;
    emit SetTransferrableEvent(transferrable);
  }

  function setSwapRouter(ISwapRouter _swapRouter) external onlyOwner {
    swapRouter = _swapRouter;
    emit SetSwapRouterEvent(swapRouter);
  }

  function setMintFee(uint256 _mintFee) external onlyOwner {
    // audit(B): L01
    _require(_mintFee <= 1e18, Errors.FEE_TOO_HIGH);
    mintFee = _mintFee;
    emit SetMintFeeEvent(mintFee);
  }

  function setBurnFee(uint256 _burnFee) external onlyOwner {
    // audit(B): L01
    _require(_burnFee <= 1e18, Errors.FEE_TOO_HIGH);
    burnFee = _burnFee;
    emit SetBurnFeeEvent(burnFee);
  }

  function collectAccruedFee() external onlyOwner nonReentrant {
    uint256 _accruedFee = accruedFee;
    accruedFee = 0;
    baseToken.transferFixed(msg.sender, _accruedFee);
    emit CollectAccruedFeeEvent(_accruedFee);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function addRewardToken(IMintable _rewardToken) external onlyOwner {
    _addRewardToken(_rewardToken);
  }

  function removeRewardToken(IMintable _rewardToken) external onlyOwner {
    _removeRewardToken(_rewardToken);
  }

  function amendBalanceBaseByStaker(
    address user,
    IMintable _rewardToken,
    uint256 _base
  ) external onlyOwner {
    uint256 oldBase = _balanceBaseByStaker[user][_rewardToken];
    _balanceBaseByStaker[user][_rewardToken] = _base;
    emit AmendBalanceBaseByStakerEvent(
      user,
      address(_rewardToken),
      oldBase,
      _base
    );
  }

  // privilidged functions

  function transferBase(
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    baseToken.transferFixed(_to, _amount);
  }

  function transferFromPool(
    address _token,
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    _require(_token == address(baseToken), Errors.TOKEN_MISMATCH);
    baseToken.transferFixed(_to, _amount);
  }

  // external functions

  function stake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _stake(msg.sender, amount);
  }

  function stake(
    address _user,
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _require(tx.origin == _user, Errors.APPROVED_ONLY);
    _stake(_user, amount);
  }

  function unstake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _unstake(msg.sender, amount);
  }

  function claim()
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _claim(msg.sender);
  }

  function claim(
    address _user
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _claim(_user);
  }

  function claim(
    address _user,
    address _rewardToken
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
  {
    _claim(_user, _rewardToken);
  }

  function mint(
    uint256 amountIn
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _mint(msg.sender, amountIn, 0, address(baseToken), 0);
  }

  function mint(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _mint(msg.sender, amountIn, amountOutMinimum, tokenIn, poolFee);
  }

  function mintAndStake(
    uint256 amountIn
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _mintAndStake(msg.sender, amountIn, 0, address(baseToken), 0);
  }

  function mintAndStake(
    address sender,
    uint256 amountIn
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    _require(tx.origin == sender, Errors.APPROVED_ONLY);
    _mintAndStake(sender, amountIn, 0, address(baseToken), 0);
  }

  function mintAndStake(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _mintAndStake(msg.sender, amountIn, amountOutMinimum, tokenIn, poolFee);
  }

  function mintAndStake(
    address sender,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) external whenNotPaused nonReentrant whenStakingNotPaused onlyAllowlisted {
    _require(tx.origin == sender, Errors.APPROVED_ONLY);
    _mintAndStake(sender, amountIn, amountOutMinimum, tokenIn, poolFee);
  }

  function burnRequest(
    uint256 _amount
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    uint256 burnStart = block.number.add(graceBlocks);
    uint256 burnExpiry = burnStart.add(requestExpireBlocks);
    uint256 salt = _burnRequestCounter.current();
    _burnRequestCounter.increment();
    BurnRequest memory request = BurnRequest(
      msg.sender,
      (block.number).toUint64(),
      burnStart.toUint64(),
      burnExpiry.toUint64(),
      _amount,
      salt
    );

    bytes32 requestHash = keccak256(abi.encode(request));
    _burnRequests[requestHash] = request;
    emit BurnRequestEvent(msg.sender, msg.sender, requestHash, request);
  }

  function burn(
    uint256 _amount
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _require(!burnRequestOn, Errors.REQUIRE_BURN_REQUEST);
    _burn(_amount, 0, address(baseToken), 0);
  }

  function burn(
    uint256 _amount,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _require(!burnRequestOn, Errors.REQUIRE_BURN_REQUEST);
    _burn(_amount, amountOutMinimum, tokenOut, poolFee);
  }

  function burn(
    bytes32 requestHash,
    uint256 _amount
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _require(
      msg.sender == _burnRequests[requestHash].requestor,
      Errors.APPROVED_ONLY
    );
    _burn(requestHash, _amount, 0, address(baseToken), 0);
  }

  function burn(
    bytes32 requestHash,
    uint256 _amount,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) external whenNotPaused nonReentrant onlyAllowlisted notContract {
    _require(
      msg.sender == _burnRequests[requestHash].requestor,
      Errors.APPROVED_ONLY
    );
    _burn(requestHash, _amount, amountOutMinimum, tokenOut, poolFee);
  }

  function unstakeAndBurn(
    uint256 amountIn
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _require(!burnRequestOn, Errors.REQUIRE_BURN_REQUEST);
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _unstake(msg.sender, amountIn);
    _burn(amountIn, 0, address(baseToken), 0);
  }

  function unstakeAndBurn(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _require(!burnRequestOn, Errors.REQUIRE_BURN_REQUEST);
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _unstake(msg.sender, amountIn);
    _burn(amountIn, amountOutMinimum, tokenOut, poolFee);
  }

  function unstakeAndBurn(
    bytes32 requestHash,
    uint256 amountIn
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _require(
      msg.sender == _burnRequests[requestHash].requestor,
      Errors.APPROVED_ONLY
    );
    _unstake(msg.sender, amountIn);
    _burn(requestHash, amountIn, 0, address(baseToken), 0);
  }

  function unstakeAndBurn(
    bytes32 requestHash,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  )
    external
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    onlyAllowlisted
    notContract
  {
    _require(
      amountIn <= _stakedByStaker[msg.sender],
      Errors.INVALID_BURN_AMOUNT
    );
    _require(
      msg.sender == _burnRequests[requestHash].requestor,
      Errors.APPROVED_ONLY
    );
    _unstake(msg.sender, amountIn);
    _burn(requestHash, amountIn, amountOutMinimum, tokenOut, poolFee);
  }

  function getBaseBalance() external view returns (uint256) {
    return _getBaseBalance();
  }

  function getBurnRequest(
    bytes32 requestHash
  ) external view returns (BurnRequest memory) {
    return _burnRequests[requestHash];
  }

  // internal functions

  function _mintAndStake(
    address sender,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) internal {
    uint256 minted = _mint(
      sender,
      amountIn,
      amountOutMinimum,
      tokenIn,
      poolFee
    );
    _stake(sender, minted);
  }

  function _mint(
    address user,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenIn,
    uint24 poolFee
  ) internal returns (uint256) {
    uint256 baseBalance = _getBaseBalance();
    uint256 balance = ERC20PausableUpgradeable(this).totalSupplyFixed();
    uint256 amountGross = amountIn;

    if (tokenIn == address(baseToken)) {
      baseToken.transferFromFixed(user, address(this), amountGross);
    } else {
      _require(approvedToken[tokenIn], Errors.APPROVED_TOKEN_ONLY);
      ERC20(tokenIn).transferFromFixed(user, address(this), amountIn);
      // audit(B): H02
      uint256 _amountIn = amountIn.min(
        ERC20(tokenIn).balanceOfFixed(address(this))
      );
      ERC20(tokenIn).approveFixed(address(swapRouter), _amountIn);

      amountGross = swapRouter.swapGivenIn(
        ISwapRouter.SwapGivenInInput(
          tokenIn,
          address(baseToken),
          amountIn,
          amountOutMinimum,
          poolFee
        )
      );
    }
    uint256 fee = amountGross.mulDown(mintFee);
    uint256 amountNet = amountGross.sub(fee);
    accruedFee += fee;
    uint256 returnBalance = baseBalance == 0
      ? amountNet
      : amountNet.mulDown(balance).divDown(baseBalance);

    // audit(B): H01
    _require(returnBalance != 0, Errors.INVALID_MINT_AMOUNT);

    _mint(user, returnBalance);

    emit MintEvent(user, user, amountGross, returnBalance, _getBaseBalance());

    return returnBalance;
  }

  function _burn(
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) internal {
    uint256 thisBalance = ERC20PausableUpgradeable(this).totalSupplyFixed();

    _require(
      amountIn <= ERC20PausableUpgradeable(this).balanceOfFixed(msg.sender),
      Errors.INVALID_BURN_AMOUNT
    );
    _require(thisBalance > 0, Errors.NOTHING_TO_BURN);

    uint256 baseBalance = _getBaseBalance();

    uint256 returnBalanceGross = amountIn.mulDown(baseBalance).divDown(
      thisBalance
    );

    _require(
      baseBalance.sub(registry.minCollateral()) >= returnBalanceGross,
      Errors.BURN_EXCEEDS_EXCESS
    );

    uint256 fee = returnBalanceGross.mulDown(burnFee);
    uint256 returnBalanceNet = returnBalanceGross.sub(fee);
    accruedFee += fee;

    _burn(msg.sender, amountIn);

    if (tokenOut == address(baseToken)) {
      baseToken.transferFixed(msg.sender, returnBalanceNet);
    } else {
      baseToken.approveFixed(address(swapRouter), returnBalanceNet);
      ERC20(tokenOut).transferFixed(
        msg.sender,
        swapRouter.swapGivenIn(
          ISwapRouter.SwapGivenInInput(
            address(baseToken),
            tokenOut,
            returnBalanceNet,
            amountOutMinimum,
            poolFee
          )
        )
      );
    }

    emit BurnEvent(msg.sender, amountIn, returnBalanceNet, _getBaseBalance());
  }

  function _burn(
    bytes32 requestHash,
    uint256 amountIn,
    uint256 amountOutMinimum,
    address tokenOut,
    uint24 poolFee
  ) internal {
    BurnRequest memory request = _burnRequests[requestHash];

    _require(
      block.number >= request.burnBlock &&
        block.number <= request.expiryBlock &&
        amountIn <= request.amount,
      Errors.APPROVED_ONLY
    );

    request.amount = request.amount.sub(amountIn);
    _burnRequests[requestHash] = request;

    _burn(amountIn, amountOutMinimum, tokenOut, poolFee);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused canTransfer {
    super._transfer(from, to, amount);
  }

  function _getBaseBalance() private view returns (uint256) {
    return baseToken.balanceOfFixed(address(this)).sub(accruedFee);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  )
    internal
    virtual
    override(ERC20Upgradeable, ERC20PausableUpgradeable)
    whenNotPaused
    canTransfer
  {
    super._beforeTokenTransfer(from, to, amount);
  }
}

