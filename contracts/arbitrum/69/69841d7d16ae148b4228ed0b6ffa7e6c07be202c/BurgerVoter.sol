// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./IVe.sol";
import "./IVoter.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./IGauge.sol";
import "./IFactory.sol";
import "./IPair.sol";
import "./IBribeFactory.sol";
import "./IGaugeFactory.sol";
import "./IMinter.sol";
import "./IBribe.sol";
import "./IMultiRewardsPool.sol";
import "./Reentrancy.sol";
import "./SafeERC20.sol";

contract BurgerVoter is IVoter, Reentrancy {
  using SafeERC20 for IERC20;

  /// @dev The ve token that governs these contracts
  address public immutable override ve;
  /// @dev BurgerFactory
  address public immutable factory;
  address public immutable token;
  address public immutable gaugeFactory;
  address public immutable bribeFactory;
  /// @dev Rewards are released over 7 days
  uint internal constant DURATION = 7 days;
  address public minter;
  address public governor;
  address public treasury;
  address public ms; // team-governor-council-treasury multi-sig
  address public emergencyCouncil;

  address public protocolFeesTaker;
  uint public protocolFeesPerMillion;

  /// @dev Total voting weight
  uint public totalWeight;

  /// @dev All pools viable for incentives
  address[] public pools;
  /// @dev pool => gauge
  mapping(address => address) public gauges;
  /// @dev gauge => pool
  mapping(address => address) public poolForGauge;
  /// @dev gauge => bribe
  mapping(address => address) public bribes;
  /// @dev pool => weight
  mapping(address => int256) public weights;
  /// @dev nft => pool => votes
  mapping(uint => mapping(address => int256)) public votes;
  /// @dev nft => pools
  mapping(uint => address[]) public poolVote;
  /// @dev nft => total voting weight of user
  mapping(uint => uint) public usedWeights;
  mapping(uint => uint) public lastVoted; // nft => timestamp of last vote, to ensure one vote per epoch
  mapping(address => bool) public isGauge;
  mapping(address => bool) public isWhitelisted;

  uint public index;
  mapping(address => uint) public supplyIndex;
  mapping(address => uint) public claimable;
  mapping(address => bool) public isAlive; // killed implies no emission allocation

  bool internal _locked;	/// @dev simple re-entrancy check

  mapping(address => bool) public unvotable; // disable voting for certain pools
  mapping(address => bool) public gaugable; // enable creation for pools with one of these constituents
  bool public pokable; // toggle poking
  address[] public whitelistings;

  event GaugeCreated(address indexed gauge, address creator, address indexed bribe, address indexed pool);
  event GaugeKilled(address indexed gauge);
  event GaugeRevived(address indexed gauge);
  event Voted(address indexed voter, uint tokenId, int256 weight);
  event Abstained(uint tokenId, int256 weight);
  event Deposit(address indexed lp, address indexed gauge, uint tokenId, uint amount);
  event Withdraw(address indexed lp, address indexed gauge, uint tokenId, uint amount);
  event NotifyReward(address indexed sender, address indexed reward, uint amount);
  event DistributeReward(address indexed sender, address indexed gauge, uint amount);
  event Attach(address indexed owner, address indexed gauge, uint tokenId);
  event Detach(address indexed owner, address indexed gauge, uint tokenId);
  event Whitelisted(address indexed whitelister, address indexed token);

  constructor(address _ve, address _factory, address _gaugeFactory, address _bribeFactory) {
    ve = _ve;
    factory = _factory;
    token = IVe(_ve).token();
    gaugeFactory = _gaugeFactory;
    bribeFactory = _bribeFactory;
    minter = msg.sender;
    treasury = msg.sender;
    ms = msg.sender;
    governor = msg.sender;
    emergencyCouncil = msg.sender;
    protocolFeesTaker = msg.sender;
  }

  modifier onlyNewEpoch(uint _tokenId) {
        // ensure new epoch since last vote
        require((block.timestamp / DURATION) * DURATION > lastVoted[_tokenId], "TOKEN_ALREADY_VOTED_THIS_EPOCH");
        _;
    }

  function initialize(address[] memory _tokens, address _minter) external {
    require(msg.sender == minter, "!minter");
    for (uint i = 0; i < _tokens.length; i++) {
      _whitelist(_tokens[i]);
    }
    minter = _minter;
  }

  function setTreasury(address _treasury) external {
    require(msg.sender == treasury, "!treasury");
    treasury = _treasury;
  }

  /// @dev Remove all votes for given tokenId.
  function reset(uint _tokenId) external onlyNewEpoch(_tokenId) {
    require(IVe(ve).isApprovedOrOwner(msg.sender, _tokenId), "!owner");
    lastVoted[_tokenId] = block.timestamp;
    _reset(_tokenId);
    IVe(ve).abstain(_tokenId);
  }

  function resetOverride(uint[] memory _ids) external {
    	for(uint i=0;i<_ids.length;i++) {
    		resetOverride(_ids[i]);
    	}
    }

    function resetOverride(uint _tokenId) public {
        require(msg.sender == governor, "Not governor");
        _reset(_tokenId);
        IVe(ve).abstain(_tokenId);
    }

    function _reset(uint _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint _poolVoteCnt = _poolVote.length;
        int256 _totalWeight = 0;

        for (uint i = 0; i < _poolVoteCnt; i ++) {
            address _pool = _poolVote[i];
            int256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                if (_votes > 0) {
                    IBribe(bribes[gauges[_pool]])._withdraw(uint256(_votes), _tokenId);
                    _totalWeight += _votes;
                } else {
                    _totalWeight -= _votes;
                }
                emit Abstained(_tokenId, _votes);
            }
        }
        totalWeight -= uint256(_totalWeight);
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }

  /// @dev Resubmit exist votes for given token. For internal purposes.
  function poke(uint _tokenId) external {
    /// Poke function was depreciated in v1.3.0 due to security reasons.
    /// Its still callable for backwards compatibility, but does nothing.
    /// Usage allowed by ms (Official Equălizer Team Multi-Sig) or Public when pokable.
    if(pokable || msg.sender == ms) {
        address[] memory _poolVote = poolVote[_tokenId];
        uint _poolCnt = _poolVote.length;
        int256[] memory _weights = new int256[](_poolCnt);

        for (uint i = 0; i < _poolCnt; i ++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }
  }

  function _vote(uint _tokenId, address[] memory _poolVote, int256[] memory _weights) internal {
      ///v1.3.1 Emergency Upgrade
    	///Prevent voting for specific "unvotable" pools
    	for(uint lol=0;lol<_poolVote.length;lol++) {
    		require(
    			! unvotable[ _poolVote[lol] ],
    			"This pool is unvotable!"
    		);
    		require(
    		    isAlive[ gauges[_poolVote[lol] ] ] ,
    		    "Cant vote for Killed Gauges!"
    		);
    	}
    
    _reset(_tokenId);
    uint _poolCnt = _poolVote.length;
    int256 _weight = int256(IVe(ve).balanceOfNFT(_tokenId));
    int256 _totalVoteWeight = 0;
    int256 _totalWeight = 0;
    int256 _usedWeight = 0;

    for (uint i = 0; i < _poolCnt; i++) {
      _totalVoteWeight += _weights[i] > 0 ? _weights[i] : - _weights[i];
    }

    for (uint i = 0; i < _poolCnt; i++) {
      address _pool = _poolVote[i];
      address _gauge = gauges[_pool];

      if (isGauge[_gauge]) {
        int256 _poolWeight = _weights[i] * _weight / _totalVoteWeight;
        require(votes[_tokenId][_pool] == 0, "duplicate pool");
        require(_poolWeight != 0, "zero power");
        _updateFor(_gauge);

        poolVote[_tokenId].push(_pool);

        weights[_pool] += _poolWeight;
        votes[_tokenId][_pool] += _poolWeight;
        if (_poolWeight > 0) {
          IBribe(bribes[_gauge])._deposit(uint(_poolWeight), _tokenId);
        } else {
          _poolWeight = - _poolWeight;
        }
        _usedWeight += _poolWeight;
        _totalWeight += _poolWeight;
        emit Voted(msg.sender, _tokenId, _poolWeight);
      }
    }
    if (_usedWeight > 0) IVe(ve).voting(_tokenId);
    totalWeight += uint(_totalWeight);
    usedWeights[_tokenId] = uint(_usedWeight);
  }

  /// @dev Vote for given pools using a vote power of given tokenId. Reset previous votes.
  function vote(uint tokenId, address[] calldata _poolVote, int256[] calldata _weights) external onlyNewEpoch(tokenId) {
    require(IVe(ve).isApprovedOrOwner(msg.sender, tokenId), "!owner");
    require(_poolVote.length == _weights.length, "!arrays");
    lastVoted[tokenId] = block.timestamp;
    _vote(tokenId, _poolVote, _weights);
  }

  /// @dev Add token to whitelist. Only pools with whitelisted tokens can be added to gauge.
  function whitelist(address _token) external {
    require(msg.sender == treasury, "!treasury");
    _whitelist(_token);
  }

  function _whitelist(address _token) internal {
    require(!isWhitelisted[_token], "already whitelisted");
    isWhitelisted[_token] = true;
    emit Whitelisted(msg.sender, _token);
  }

  /// @dev Create gauge for given pool. Only for a pool with whitelisted tokens.
  function createGauge(address _pool) external returns (address) {
    require(gauges[_pool] == address(0x0), "exists");
    address[] memory allowedRewards = new address[](3);
    bool isPair = IFactory(factory).isPair(_pool);
    address tokenA;
    address tokenB;


    if (isPair) {
        (tokenA, tokenB) = IPair(_pool).tokens();
        allowedRewards[0] = tokenA;
        allowedRewards[1] = tokenB;
        if (token != tokenA && token != tokenB) {
          allowedRewards[2] = token;
        }
    }
    else {
    	allowedRewards[0] = token;
    }

    if (msg.sender != governor) { // gov can create for any pool, even non-Hamburger pairs
      require(isPair, "!_pool");
      require(isWhitelisted[tokenA] && isWhitelisted[tokenB], "!whitelisted");
    	require(gaugable[tokenA] || gaugable[tokenB], "Pool not Gaugable!");
    	require(IPair(_pool).stable()==false, "Creation of Stable-pool Gauge not allowed!");
    }

    address _bribe = IBribeFactory(bribeFactory).createBribe(allowedRewards);
    address _gauge = IGaugeFactory(gaugeFactory).createGauge(_pool, _bribe, ve, allowedRewards);
    IERC20(token).approve(_gauge, type(uint).max);
    bribes[_gauge] = _bribe;
    gauges[_pool] = _gauge;
    poolForGauge[_gauge] = _pool;
    isGauge[_gauge] = true;
    isAlive[_gauge] = true;
    _updateFor(_gauge);
    pools.push(_pool);
    emit GaugeCreated(_gauge, msg.sender, _bribe, _pool);
    return _gauge;
  }

  
  function createGaugeMultiple(address[] memory _pools) external returns (address[] memory) {
  	address[] memory _g_c = new address[](_pools.length);
      for(uint _j; _j<_pools.length; _j++) {
          _g_c[_j] = this.createGauge(_pools[_j]);
      }
      return _g_c;
  }


  function killGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        claimable[_gauge] = 0;
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

  /// @dev A gauge should be able to attach a token for preventing transfers/withdraws.
  function attachTokenToGauge(uint tokenId, address account) external override {
    require(isGauge[msg.sender], "!gauge");
    require(isAlive[msg.sender], "killed gauge"); // killed gauges cannot attach tokens to themselves
    if (tokenId > 0) {
      IVe(ve).attachToken(tokenId);
    }
    emit Attach(account, msg.sender, tokenId);
  }

  /// @dev Emit deposit event for easily handling external actions.
  function emitDeposit(uint tokenId, address account, uint amount) external override {
    require(isGauge[msg.sender], "!gauge");
    require(isAlive[msg.sender], "killed gauge");
    emit Deposit(account, msg.sender, tokenId, amount);
  }

  /// @dev Detach given token.
  function detachTokenFromGauge(uint tokenId, address account) external override {
    require(isGauge[msg.sender], "!gauge");
    if (tokenId > 0) {
      IVe(ve).detachToken(tokenId);
    }
    emit Detach(account, msg.sender, tokenId);
  }

  /// @dev Emit withdraw event for easily handling external actions.
  function emitWithdraw(uint tokenId, address account, uint amount) external override {
    require(isGauge[msg.sender], "!gauge");
    emit Withdraw(account, msg.sender, tokenId, amount);
  }

  /// @dev Length of pools
  function poolsLength() external view returns (uint) {
    return pools.length;
  }

  function whitelistedTokens() external view returns (address[] memory) {
    	address[] memory _r = new address[](whitelistings.length);
    	for(uint i;i<whitelistings.length;i++) {
    		_r[i] = whitelistings[i];
    	}
        return _r;
    }

  /// @dev Add rewards to this contract. Usually it is BurgerMinter.
  function notifyRewardAmount(uint amount) external override {
    require(amount != 0, "zero amount");
    uint _totalWeight = totalWeight;
    // without votes rewards can not be added
    require(_totalWeight != 0, "!weights");
    // transfer the distro in
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    // 1e18 adjustment is removed during claim
    uint _ratio = amount * 1e18 / _totalWeight;
    if (_ratio > 0) {
      index += _ratio;
    }
    emit NotifyReward(msg.sender, token, amount);
  }

  /// @dev Update given gauges.
  function updateFor(address[] memory _gauges) external {
    for (uint i = 0; i < _gauges.length; i++) {
      _updateFor(_gauges[i]);
    }
  }

  /// @dev Update gauges by indexes in a range.
  function updateForRange(uint start, uint end) public {
    for (uint i = start; i < end; i++) {
      _updateFor(gauges[pools[i]]);
    }
  }

  /// @dev Update all gauges.
  function updateAll() external {
    updateForRange(0, pools.length);
  }

  /// @dev Update reward info for given gauge.
  function updateGauge(address _gauge) external {
    _updateFor(_gauge);
  }

  function _updateFor(address _gauge) internal {
    address _pool = poolForGauge[_gauge];
    int256 _supplied = weights[_pool];
    if (_supplied > 0) {
      uint _supplyIndex = supplyIndex[_gauge];
      // get global index for accumulated distro
      uint _index = index;
      // update _gauge current position to global position
      supplyIndex[_gauge] = _index;
      // see if there is any difference that need to be accrued
      uint _delta = _index - _supplyIndex;
      if (_delta > 0) {
        // add accrued difference for each supplied token
        uint _share = uint(_supplied) * _delta / 1e18;
        claimable[_gauge] += _share;
      }
    } else {
      // new users are set to the default global state
      supplyIndex[_gauge] = index;
    }
  }

  /// @dev Batch claim rewards from given gauges.
  function claimRewards(address[] memory _gauges, address[][] memory _tokens) public {
    for (uint i = 0; i < _gauges.length; i++) {
      IGauge(_gauges[i]).getReward(msg.sender, _tokens[i]);
    }
  }

  /// @dev Batch claim rewards from given bribe contracts for given tokenId.
  function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) public {
    require(IVe(ve).isApprovedOrOwner(msg.sender, _tokenId), "!owner");
    for (uint i = 0; i < _bribes.length; i++) {
      IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
    }
  }

  /// @dev Claim fees from given bribes.
  function claimFees(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) external {
    require(IVe(ve).isApprovedOrOwner(msg.sender, _tokenId), "!owner");
    for (uint i = 0; i < _bribes.length; i++) {
      IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
    }
  }

  function claimEverything(
    	address[] memory _gauges, address[][] memory _gtokens,
    	address[] memory _bribes, address[][] memory _btokens, uint _tokenId
    ) external {
        claimRewards(_gauges, _gtokens);
        if(_tokenId > 0) {
            claimBribes(_bribes, _btokens, _tokenId);
        }
    }

  /// @dev Move fees from deposited pools to bribes for given gauges.
  function distributeFees(address[] memory _gauges) external {
    for (uint i = 0; i < _gauges.length; i++) {
      IGauge(_gauges[i]).claimFees();
    }
  }

  /// @dev Get emission from minter and notify rewards for given gauge.
  function distribute(address _gauge) external override {
    _distribute(_gauge);
  }

  function _distribute(address _gauge) internal lock {
    IMinter(minter).updatePeriod();
    _updateFor(_gauge);
    uint _claimable = claimable[_gauge];
    if (_claimable > IMultiRewardsPool(_gauge).left(token) && _claimable / DURATION > 0) {
      claimable[_gauge] = 0;
      IGauge(_gauge).notifyRewardAmount(token, _claimable);
      emit DistributeReward(msg.sender, _gauge, _claimable);
    }
  }

  /// @dev Distribute rewards for all pools.
  function distributeAll() external {
    uint length = pools.length;
    for (uint x; x < length; x++) {
      _distribute(gauges[pools[x]]);
    }
  }

  function distributeForPoolsInRange(uint start, uint finish) external {
    for (uint x = start; x < finish; x++) {
      _distribute(gauges[pools[x]]);
    }
  }

  function distributeForGauges(address[] memory _gauges) external {
    for (uint x = 0; x < _gauges.length; x++) {
      _distribute(_gauges[x]);
    }
  }


  /* NEW */

  function removeFromWhitelist(address[] calldata _tokens) external {
      require(msg.sender == governor, "Not governor");
      for (uint i = 0; i < _tokens.length; i++) {
          delete isWhitelisted[_tokens[i]];
          for(uint j; j<whitelistings.length;j++){
          	if(whitelistings[j]==_tokens[i]){
          		whitelistings[i] = whitelistings[whitelistings.length-1];
          		whitelistings.pop();
          	}
          }
          emit Whitelisted(msg.sender, _tokens[i]);
      }
  }

  function setGovernor(address _governor) public {
      require(msg.sender == governor, "Not governor!");
      governor = _governor;
  }

    function setEmergencyCouncil(address _council) public {
      require(msg.sender == emergencyCouncil, "Not emergency council!");
      emergencyCouncil = _council;
  }

    function setProtocolFeesTaker(address _pft) public {
      require(msg.sender == governor, "Not governor!");
      protocolFeesTaker = _pft;
  }

    function setProtocolFeesPerMillion(uint _pf) public {
      require(msg.sender == governor, "Not governor!");
      protocolFeesPerMillion = _pf;
  }

  function setGov(address _ms) external {
  	require(msg.sender == ms, "!ms");
  	governor = _ms;
      emergencyCouncil = _ms;
      protocolFeesTaker = _ms;
      ms = _ms;
  }

  function setUnvotablePools(address[] calldata _pools, bool[] calldata _b) external {
        require(msg.sender == governor, "Not governor");
        for (uint i = 0; i < _pools.length; i++) {
            unvotable [ _pools[i] ] = _b[i];
        }
    }

    function setGaugable(address[] calldata _pools, bool[] calldata _b) external {
        require(msg.sender == governor, "Not governor");
        for (uint i = 0; i < _pools.length; i++) {
            gaugable[ _pools[i] ] = _b[i];
        }
    }

  function setPokable(bool _b) external {
      require(msg.sender == governor, "Not governor");
      pokable = _b;
  }
}

