// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IGovFactory.sol";
import "./ISaleGatewayRemote.sol";
import "./IGovSaleRemote.sol";
import "./SaleLibrary.sol";

contract GovSaleRemote is
  Initializable,
  IGovSaleRemote,
  PausableUpgradeable,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

  uint256 public sold;
  uint256 public price; // in payment decimal

  uint128 public dstPaymentDecimals;
  uint128 public srcPaymentDecimals;

  uint256 public sale;
  uint256 public feeMoved;

  uint256 public raised; // sale amount get
  uint256 public revenue; // fee amount get

  uint256 public minFCFSBuy;
  uint256 public maxFCFSBuy;

  uint256 public minComBuy;
  uint256 public maxComBuy;

  uint256 public whitelistTotalAlloc;
  uint256 public voteTotalStaked;

  uint256 internal booster1Achieved;

  address[] public whitelists;
  address[] public stakers; // valid stakers only
  address[] public candidates;
  address[] public users; // valid buyers

  bool public isFinalized;
  address public targetSale;
  ISaleGatewayRemote public saleGateway;
  IGovFactory public factory;
  IERC20MetadataUpgradeable public payment;

  struct Round {
    uint128 start;
    uint128 end;
    uint256 fee_d2; // in percent 2 decimal
  }

  struct Summary {
    uint256 received; // token received
    uint256 bought; // payment given
    uint256 feeGiven;
  }

  mapping(uint128 => Round) public booster;

  mapping(uint240 => uint256) public chainStaked; // staked amount each chain
  mapping(uint240 => mapping(address => uint256)) public candidateChainStaked; // candidate staked amount each chain

  mapping(address => uint256) public stakerIndex; // staker index
  mapping(address => uint256) public whitelist; // whitelist amount

  mapping(address => bool) public isUser;

  mapping(address => string) public recipient;
  mapping(address => Summary) public summaries;
  mapping(address => mapping(uint128 => uint256)) public purchasedPerRound;

  // ========  vote
  bytes32 internal constant FORM_TYPEHASH = keccak256('Form(address from,string content)');

  uint128 public voteStart;
  uint128 public voteEnd;

  bytes32 public DOMAIN_SEPARATOR;
  string public name;
  string public version;
  string public message;

  mapping(address => bool) public isVoteValid;

  struct Form {
    address from;
    string content;
  }
  // ========  vote

  event TokenBought(
    uint128 indexed booster,
    address indexed user,
    uint256 tokenReceived,
    uint256 buyAmount,
    uint256 feeCharged
  );

  event Finalize(uint256 remoteRaised, uint256 remoteRevenue, uint256 remoteSold);

  /**
   * @dev Initialize project for raise fund
   * @param _start Epoch date to start round 1
   * @param _duration Duration per booster (in seconds)
   * @param _sale Amount token project to sell (based on token decimals of project)
   * @param _price Token project price in payment decimal
   * @param _fee_d2 Fee project percent in each rounds in 2 decimal
   * @param _payment Tokens to raise
   * @param _targetSale Tokens to raise
   */
  function init(
    uint128 _start,
    uint128 _duration,
    uint256 _sale,
    uint256 _price,
    uint256[4] memory _fee_d2,
    address _payment,
    string[3] calldata _nameVersionMsg,
    uint128[2] calldata _voteStartEnd,
    uint128 _dstPaymentDecimals,
    address _targetSale
  ) external initializer {
    __Pausable_init();
    __ReentrancyGuard_init();

    sale = _sale;
    price = _price;
    payment = IERC20MetadataUpgradeable(_payment);
    message = _nameVersionMsg[2];
    voteStart = _voteStartEnd[0];
    voteEnd = _voteStartEnd[1];
    dstPaymentDecimals = _dstPaymentDecimals;
    targetSale = _targetSale;

    factory = IGovFactory(_msgSender());
    saleGateway = ISaleGatewayRemote(factory.saleGateway());
    srcPaymentDecimals = payment.decimals();

    _createDomain(_nameVersionMsg[0], _nameVersionMsg[1]);
    _transferOwnership(factory.owner());

    uint128 i = 1;
    do {
      if (i == 1) {
        booster[i].start = _start;
      } else {
        booster[i].start = booster[i - 1].end + 1;
      }
      if (i < 4) booster[i].end = booster[i].start + _duration;
      booster[i].fee_d2 = _fee_d2[i - 1];

      ++i;
    } while (i <= 4);
  }

  // **** VIEW AREA ****

  /**
   * @dev Get all buyers/participants length
   */
  function usersLength() external view virtual returns (uint256) {
    return users.length;
  }

  /**
   * @dev Get all stakers length
   */
  function stakersLength() external view virtual returns (uint256) {
    return stakers.length;
  }

  /**
   * @dev Get all whitelists length
   */
  function whitelistsLength() external view virtual returns (uint256) {
    return whitelists.length;
  }

  /**
   * @dev Get all candidates length
   */
  function candidatesLength() external view virtual returns (uint256) {
    return candidates.length;
  }

  /**
   * @dev Get booster running now, 0 = no booster running
   */
  function boosterProgress() public view virtual returns (uint128 running) {
    for (uint128 i = 1; i <= 4; ++i) {
      if (
        (uint128(block.timestamp) >= booster[i].start && uint128(block.timestamp) <= booster[i].end) ||
        (i == 4 && uint128(block.timestamp) >= booster[i].start)
      ) {
        running = i;
        break;
      }
    }
  }

  /**
   * @dev Get payload
   * @param _amountIn Amount to buy
   * @param _user User address
   */
  function _payload(uint256 _amountIn, address _user) internal view virtual returns (bytes memory payload) {
    // change to 6 decimal
    _amountIn = (_amountIn * (10 ** dstPaymentDecimals)) / 10 ** srcPaymentDecimals;
    payload = abi.encode(uint240(block.chainid), targetSale, _amountIn, _user);
  }

  /**
   * @dev Estimate cross chain fees
   * @param _amountIn Amount to buy
   * @param _user User address
   */
  function estimateCrossFee(uint256 _amountIn, address _user) public view virtual returns (uint256 fees, uint256 tax) {
    fees = saleGateway.estimateFees(_payload(_amountIn, _user));
    tax = SaleLibrary.calcPercent2Decimal(saleGateway.crossFee_d2(), fees);
  }

  /**
   * @dev Get User Total Staked Kom
   * @param _user User address
   */
  function candidateTotalStaked(address _user) public view virtual returns (uint256 userTotalStakedAmount) {
    uint256 chainStakedLength = factory.allChainsStakedLength();
    for (uint256 i = 0; i < chainStakedLength; ++i) {
      userTotalStakedAmount += candidateChainStaked[uint240(factory.allChainsStaked(i))][_user];
    }
  }

  function _formatOrigin(uint256 _amount) internal view virtual returns (uint256 result) {
    result = (_amount * (10 ** srcPaymentDecimals)) / 10 ** dstPaymentDecimals;
  }

  /**
   * @dev Get User Total Staked Allocation
   * @param _user User address
   * @param _boosterRunning Booster progress
   */
  function calcUserAllocation(address _user, uint128 _boosterRunning) public view virtual returns (uint256 userAlloc) {
    uint256 saleAmount = sale;
    uint256 candidateStakedToken = candidateTotalStaked(_user);
    bool isVoter = isVoteValid[_user];

    if (_boosterRunning == 1) {
      if (candidateStakedToken > 0 && isVoter) {
        userAlloc = SaleLibrary.calcAllocFromKom(
          candidateStakedToken,
          voteTotalStaked,
          saleAmount - whitelistTotalAlloc
        );
      }

      uint256 whitelistAmount = whitelist[_user];

      if (whitelistAmount > 0) userAlloc += whitelistAmount;
    } else if (_boosterRunning == 2) {
      if (uint128(block.timestamp) >= booster[2].start && candidateStakedToken > 0 && isVoter) {
        userAlloc = SaleLibrary.calcAllocFromKom(candidateStakedToken, voteTotalStaked, saleAmount - booster1Achieved);
      }
    } else if (_boosterRunning == 3) {
      if ((stakers.length > 0 && stakers[stakerIndex[_user]] == _user) || whitelist[_user] > 0) userAlloc = maxFCFSBuy;
    } else if (_boosterRunning == 4) {
      userAlloc = maxComBuy;
    }
  }

  /**
   * @dev Calculate amount in
   * @param _tokenReceived Token received amount
   * @param _user User address
   * @param _running Booster running
   * @param _boosterPrice Booster running price
   */
  function _amountInCalc(
    uint256 _alloc,
    uint256 _tokenReceived,
    address _user,
    uint128 _running,
    uint256 _boosterPrice
  ) internal view virtual returns (uint256 amountInFinal, uint256 tokenReceivedFinal) {
    uint256 left = sale - sold;

    if (_tokenReceived > left) _tokenReceived = left;

    amountInFinal = SaleLibrary.calcAmountIn(_tokenReceived, _boosterPrice);

    if (_running == 3) {
      require(maxFCFSBuy > 0 && _tokenReceived >= minFCFSBuy, '<min');
    } else if (_running == 4) {
      require(maxComBuy > 0 && _tokenReceived >= minComBuy, '<min');
    }

    uint256 purchaseThisRound = purchasedPerRound[_user][_running];

    if (purchaseThisRound + _tokenReceived > _alloc)
      amountInFinal = SaleLibrary.calcAmountIn(_alloc - purchaseThisRound, _boosterPrice);

    require(purchaseThisRound < _alloc && amountInFinal > 0, 'nope');

    tokenReceivedFinal = SaleLibrary.calcTokenReceived(amountInFinal, _boosterPrice);
  }

  function _isEligible() internal view virtual {
    require((_msgSender() == factory.savior() || _msgSender() == owner()), '??');
  }

  function _isSufficient(uint256 _amount) internal view virtual {
    require(payment.balanceOf(address(this)) >= _amount, 'less');
  }

  function _isNotStarted() internal view virtual {
    require(uint128(block.timestamp) < booster[1].start, 'started');
  }

  // **** MAIN AREA ****

  function _releaseToken(address _target, uint256 _amount) internal virtual {
    payment.safeTransfer(_target, _amount);
  }

  /**
   * @dev Move raised fund to devAddr/project owner
   */
  function moveFund(uint256 _percent_d2, bool _devAddr, address _target) external virtual {
    _isEligible();

    uint256 amount = SaleLibrary.calcPercent2Decimal(raised, _percent_d2);

    _isSufficient(amount);
    require(isFinalized, 'bad');

    if (_devAddr) {
      _releaseToken(factory.operational(), amount);
    } else {
      _releaseToken(_target, amount);
    }
  }

  function forceMoveFund() external virtual {
    _isEligible();

    _releaseToken(factory.operational(), payment.balanceOf(address(this)));
  }

  /**
   * @dev Move fee to devAddr
   */
  function moveFee() external virtual {
    _isEligible();

    uint256 amount = revenue;
    uint256 left = amount - feeMoved;

    _isSufficient(left);

    require(left > 0 && isFinalized, 'bad');

    feeMoved = amount;

    _releaseToken(factory.operational(), SaleLibrary.calcPercent2Decimal(left, factory.operationalPercentage_d2()));
    _releaseToken(factory.marketing(), SaleLibrary.calcPercent2Decimal(left, factory.marketingPercentage_d2()));
    _releaseToken(factory.treasury(), SaleLibrary.calcPercent2Decimal(left, factory.treasuryPercentage_d2()));
  }

  /**
   * @dev Buy token project using token raise
   * @param _amountIn Buy amount
   */
  function buyToken(uint256 _amountIn) external payable virtual whenNotPaused nonReentrant {
    address user = _msgSender();
    uint128 running = boosterProgress();
    require(running > 0, '!booster');

    if (running < 3) require(voteTotalStaked > 0, '!voteStaked');

    uint256 calcAllocation = calcUserAllocation(user, running);
    require(calcAllocation > 0, '!eligible');

    uint256 boosterPrice = price;

    (uint256 amountInFinal, uint256 tokenReceivedFinal) = _amountInCalc(
      calcAllocation,
      SaleLibrary.calcTokenReceived(_amountIn, boosterPrice),
      user,
      running,
      boosterPrice
    );

    (uint256 crossFee, uint256 crossTax) = estimateCrossFee(amountInFinal, user);
    uint256 crossFeeNeeded = crossFee + crossTax;
    uint256 crossFeeIn = msg.value;

    require(crossFeeIn >= crossFeeNeeded, '!crossFee');

    uint256 feeCharged;
    if (whitelist[user] == 0) feeCharged = SaleLibrary.calcPercent2Decimal(amountInFinal, booster[running].fee_d2);

    raised += amountInFinal;
    revenue += feeCharged;
    sold += tokenReceivedFinal;
    if (running == 1) booster1Achieved += tokenReceivedFinal;

    summaries[user].received += tokenReceivedFinal;
    summaries[user].bought += amountInFinal;
    summaries[user].feeGiven += feeCharged;

    if (!isUser[user]) {
      isUser[user] = true;
      users.push(user);
    }

    if (crossFeeIn > crossFeeNeeded) {
      (bool success, ) = payable(user).call{value: crossFeeIn - crossFeeNeeded}('');
      require(success, 'fail');
    }

    payment.safeTransferFrom(user, address(this), amountInFinal + feeCharged);
    saleGateway.buyToken{value: crossFeeNeeded}(_payload(amountInFinal, user), crossTax);

    emit TokenBought(running, user, tokenReceivedFinal, amountInFinal, feeCharged);
  }

  function finalize(bytes memory _salePayload) external virtual whenPaused {
    require(_msgSender() == owner(), '!caller');

    (
      uint240 chainID,
      uint256 remoteRaised,
      uint256 remoteRevenue,
      uint256 remoteSold,
      address[] memory remoteUsers,
      uint256[] memory remoteUsersBought,
      uint256[] memory remoteUsersReceived,
      uint256[] memory remoteUsersFee
    ) = abi.decode(_salePayload, (uint240, uint256, uint256, uint256, address[], uint256[], uint256[], uint256[]));

    require(chainID == uint240(block.chainid), '!chainID');

    raised = _formatOrigin(remoteRaised);
    revenue = _formatOrigin(remoteRevenue);
    sold = remoteSold;

    for (uint256 i = 0; i < remoteUsers.length; ++i) {
      address user = remoteUsers[i];
      uint256 remoteBought = _formatOrigin(remoteUsersBought[i]);
      uint256 remoteFee = _formatOrigin(remoteUsersFee[i]);
      Summary memory summary = summaries[user];

      uint256 payback;
      if (summary.bought > remoteBought) payback = summary.bought - remoteBought;

      uint256 finalFee = remoteFee;
      if (summary.feeGiven > remoteFee) {
        uint256 diff = summary.feeGiven - remoteFee;
        payback += diff;
      } else {
        finalFee = summary.feeGiven;
      }

      summaries[user] = Summary(remoteUsersReceived[i], remoteBought, finalFee);
      if (payback > 0) _releaseToken(user, payback);
    }

    isFinalized = true;

    emit Finalize(raised, revenue, sold);
  }

  /**
   * @dev Set recipient address
   * @param _recipient Recipient address
   */
  function setRecipient(string memory _recipient) external virtual whenNotPaused {
    require(boosterProgress() > 0 && bytes(_recipient).length > 0, 'bad');

    recipient[_msgSender()] = _recipient;
  }

  // **** ADMIN AREA ****

  function setStakers(address[] calldata _users) external virtual onlyOwner {
    _isNotStarted();

    for (uint256 i = 0; i < _users.length; ++i) {
      if (stakers.length > 0 && stakers[stakerIndex[_users[i]]] == _users[i]) continue;

      stakerIndex[_users[i]] = stakers.length;
      stakers.push(_users[i]);
    }
  }

  /**
   * @dev Set user total KOM staked
   * @param _users User address
   */
  function setCandidateChainStaked(
    uint240 _chainID,
    address[] calldata _users,
    uint256[] calldata _stakedAmount
  ) external virtual onlyOwner {
    _isNotStarted();

    uint240 chainID = uint240(factory.allChainsStaked(factory.getChainStakedIndex(_chainID)));

    require(_chainID == chainID && _users.length == _stakedAmount.length, 'bad');

    for (uint256 i = 0; i < _users.length; ++i) {
      if (stakers[stakerIndex[_users[i]]] != _users[i] || candidateChainStaked[_chainID][_users[i]] > 0) continue;

      candidateChainStaked[_chainID][_users[i]] = _stakedAmount[i];
      chainStaked[_chainID] += _stakedAmount[i];
    }
  }

  function resetCandidateChainStaked(uint240 _chainID, address[] calldata _users) external virtual onlyOwner {
    _isNotStarted();

    uint240 chainID = uint240(factory.allChainsStaked(factory.getChainStakedIndex(_chainID)));

    require(_chainID == chainID, '!chainID');

    for (uint256 i = 0; i < _users.length; ++i) {
      if (stakers[stakerIndex[_users[i]]] != _users[i] || candidateChainStaked[_chainID][_users[i]] == 0) continue;

      chainStaked[_chainID] -= candidateChainStaked[_chainID][_users[i]];
      delete candidateChainStaked[_chainID][_users[i]];
    }
  }

  /**
   * @dev Set whitelist allocation token in 6 decimal
   * @param _user User address
   * @param _allocation Token allocation in 6 decimal
   */
  function setWhitelist_d6(address[] calldata _user, uint256[] calldata _allocation) external virtual onlyOwner {
    _isNotStarted();
    require(_user.length == _allocation.length, 'bad');

    uint256 whitelistTotal = whitelistTotalAlloc;
    for (uint256 i = 0; i < _user.length; ++i) {
      if (whitelist[_user[i]] > 0) continue;

      whitelists.push(_user[i]);
      whitelist[_user[i]] = SaleLibrary.calcWhitelist6Decimal(_allocation[i]);
      whitelistTotal += whitelist[_user[i]];
    }

    whitelistTotalAlloc = whitelistTotal;
  }

  /**
   * @dev Update whitelist allocation token in 6 decimal
   * @param _user User address
   * @param _allocation Token allocation in 6 decimal
   */
  function updateWhitelist_d6(address[] calldata _user, uint256[] calldata _allocation) external virtual onlyOwner {
    _isNotStarted();
    require(_user.length == _allocation.length, 'bad');

    uint256 whitelistTotal = whitelistTotalAlloc;
    for (uint256 i = 0; i < _user.length; ++i) {
      if (whitelist[_user[i]] == 0) continue;

      uint256 oldAlloc = whitelist[_user[i]];
      whitelist[_user[i]] = SaleLibrary.calcWhitelist6Decimal(_allocation[i]);
      whitelistTotal = whitelistTotal - oldAlloc + whitelist[_user[i]];
    }

    whitelistTotalAlloc = whitelistTotal;
  }

  function removePurchase(address _user) external virtual onlyOwner {
    require(boosterProgress() == 4 && paused(), 'bad');

    Summary memory summary = summaries[_user];

    delete summaries[_user];

    if (!isFinalized) {
      raised -= summary.bought;
      revenue -= summary.feeGiven;
      sold -= summary.received;
    }

    _releaseToken(_user, summary.bought + summary.feeGiven);
  }

  /**
   * @dev Set Min & Max in FCFS
   * @param _minMaxFCFSBuy Min and max token to buy
   */
  function setMinMaxFCFS(uint256[2] calldata _minMaxFCFSBuy) external virtual onlyOwner {
    if (boosterProgress() < 3) minFCFSBuy = _minMaxFCFSBuy[0];
    maxFCFSBuy = _minMaxFCFSBuy[1];
  }

  /**
   * @dev Set Min & Max in Community Round
   * @param _minMaxComBuy Min and max token to buy
   */
  function setMinMaxCom(uint256[2] calldata _minMaxComBuy) external virtual onlyOwner {
    if (boosterProgress() < 4) minComBuy = _minMaxComBuy[0];
    maxComBuy = _minMaxComBuy[1];
  }

  /**
   * @dev Config sale data
   * @param _payment Tokens to raise
   * @param _start Epoch date to start round 1
   * @param _duration Duration per booster (in seconds)
   * @param _sale Amount token project to sell (based on token decimals of project)
   * @param _price Token project price in payment decimal
   * @param _fee_d2 Fee project percent in each rounds in 2 decimal
   */
  function config(
    uint128 _start,
    uint128 _duration,
    uint256 _sale,
    uint256 _price,
    uint256[4] memory _fee_d2,
    address _payment,
    uint128 _dstPaymentDecimals
  ) external virtual onlyOwner {
    require(uint128(block.timestamp) < booster[1].start, 'started');

    payment = IERC20MetadataUpgradeable(_payment);
    sale = _sale;
    price = _price;
    dstPaymentDecimals = _dstPaymentDecimals;
    srcPaymentDecimals = payment.decimals();

    uint128 i = 1;
    do {
      if (i == 1) {
        booster[i].start = _start;
      } else {
        booster[i].start = booster[i - 1].end + 1;
      }
      if (i < 4) booster[i].end = booster[i].start + _duration;
      booster[i].fee_d2 = _fee_d2[i - 1];

      ++i;
    } while (i <= 4);
  }

  function setTargetSale(address _targetSale) external virtual onlyOwner {
    targetSale = _targetSale;
  }

  /**
   * @dev Toggle buyToken pause
   */
  function togglePause() external virtual onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  // ======= vote
  function _createDomain(string memory _name, string memory _version) internal virtual {
    require(bytes(_name).length > 0 && bytes(_version).length > 0, 'bad');

    name = _name;
    version = _version;

    (uint240 chainId, , ) = saleGateway.dstChain();

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
        keccak256(bytes(_name)),
        keccak256(bytes(_version)),
        uint256(chainId),
        targetSale
      )
    );
  }

  function _hash(Form memory form) internal pure virtual returns (bytes32) {
    return keccak256(abi.encode(FORM_TYPEHASH, form.from, keccak256(bytes(form.content))));
  }

  function verify(address _from, bytes memory _signature) public view virtual returns (bool) {
    if (_signature.length != 65) return false;

    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      r := mload(add(_signature, 0x20))
      s := mload(add(_signature, 0x40))
      v := byte(0, mload(add(_signature, 0x60)))
    }

    Form memory form = Form({from: _from, content: message});

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, _hash(form)));

    if (v != 27 && v != 28) v += 27;

    return ecrecover(digest, v, r, s) == _from;
  }

  /**
   * @dev Migrate candidates from gov contract
   * @param _users Candidate address
   * param _signatures Candidate's signature
   * param _votedAt Candidate's voted at in unix time
   */
  function migrateCandidates(
    address[] calldata _users,
    bytes[] calldata _signatures,
    uint128[] calldata _votedAt
  ) external virtual onlyOwner {
    _isNotStarted();

    require(
      stakers.length > 0 &&
        _users.length == _signatures.length &&
        _users.length == _votedAt.length &&
        block.timestamp > voteEnd,
      'bad'
    );
    address komV = factory.komV();

    uint256 voteStaked = voteTotalStaked;

    for (uint256 i = 0; i < _users.length; ++i) {
      if (
        isVoteValid[_users[i]] ||
        !verify(_users[i], _signatures[i]) ||
        (komV != address(0) &&
          IERC20Upgradeable(komV).balanceOf(_users[i]) == 0 &&
          stakers[stakerIndex[_users[i]]] != _users[i]) ||
        _votedAt[i] < voteStart ||
        _votedAt[i] > voteEnd
      ) continue;

      voteStaked += candidateTotalStaked(_users[i]);
      isVoteValid[_users[i]] = true;
      candidates.push(_users[i]);
    }
    voteTotalStaked = voteStaked;
  }

  function updateVoteStart(uint128 _voteStart) external virtual onlyOwner {
    require(_voteStart > 0 && _voteStart != voteStart && block.timestamp < voteStart, 'bad');
    voteStart = _voteStart;
  }

  function updateVoteEnd(uint128 _voteEnd) external virtual onlyOwner {
    require(_voteEnd > 0 && _voteEnd != voteEnd && block.timestamp < voteEnd, 'bad');
    voteEnd = _voteEnd;
  }
  // ======= vote
}

