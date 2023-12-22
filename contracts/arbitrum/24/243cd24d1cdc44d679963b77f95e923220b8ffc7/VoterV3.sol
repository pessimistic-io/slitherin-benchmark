// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IBribe.sol";
import "./IBribeFactory.sol";
import "./IGauge.sol";
import "./IGaugeFactory.sol";
import "./IERC20.sol";
import "./IMinter.sol";
import "./IPairInfo.sol";
import "./IPairFactory.sol";
import "./IVotingEscrow.sol";
import "./IPermissionsRegistry.sol";
import "./IUniV3Factory.sol";
import "./Strings.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

contract VoterV3 is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    bool internal initflag;

    address public _ve;                                         // the ve token that governs these contracts
    address[] internal _factories;                                 // Array with all the pair factories
    address internal base;                                      // $horiza token
    address[] internal _gaugeFactories;                            // array with all the gauge factories
    address public bribefactory;                                // bribe factory (internal and external)
    address public minter;                                      // minter mints $horiza each epoch
    address public permissionRegistry;                          // registry to check accesses
    address[] public pools;                                     // all pools viable for incentives

    uint256 internal index;                                        // gauge index
    uint256 internal constant DURATION = 7 days;                   // rewards are released over 7 days
    uint256 public VOTE_DELAY;                                     // delay between votes in seconds
    uint256 public constant MAX_VOTE_DELAY = 7 days;               // Max vote delay allowed

    mapping(address => uint256) internal supplyIndex;              // gauge    => index
    mapping(address => uint256) public claimable;                  // gauge    => claimable $horiza
    mapping(address => address) public gauges;                  // pool     => gauge
    mapping(address => uint256) public gaugesDistributionTimestmap;// gauge    => last Distribution Time
    mapping(address => address) public poolForGauge;            // gauge    => pool
    mapping(address => address) public internal_bribes;         // gauge    => internal bribe (only fees)
    mapping(address => address) public external_bribes;         // gauge    => external bribe (real bribes)
    mapping(uint256 => mapping(address => uint256)) public votes;  // nft      => pool     => votes
    mapping(uint256 => address[]) public poolVote;                 // nft      => pools
    mapping(uint256 => mapping(address => uint256)) internal weightsPerEpoch; // timestamp => pool => weights
    mapping(uint256 => uint256) internal totalWeightsPerEpoch;         // timestamp => total weights
    mapping(uint256 => uint256) public lastVoted;                     // nft      => timestamp of last vote
    mapping(address => bool) public isGauge;                    // gauge    => boolean [is a gauge?]
    mapping(address => bool) public isWhitelisted;              // token    => boolean [is an allowed token?]
    mapping(address => bool) public isAlive;                    // gauge    => boolean [is the gauge alive?]
    mapping(address => bool) public isFactory;                  // factory  => boolean [the pair factory exists?]
    mapping(address => bool) public isGaugeFactory;             // g.factory=> boolean [the gauge factory exists?]

    event GaugeCreated(address indexed gauge, address creator, address internal_bribe, address indexed external_bribe, address indexed pool);
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 tokenId, uint256 weight);
    event Abstained(uint256 tokenId, uint256 weight);
    event NotifyReward(address indexed sender, address indexed reward, uint256 amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint256 amount);
    event Whitelisted(address indexed whitelister, address indexed token);
    event Blacklisted(address indexed blacklister, address indexed token);

    event SetMinter(address indexed old, address indexed latest);
    event SetBribeFactory(address indexed old, address indexed latest);
    event SetPairFactory(address indexed old, address indexed latest);
    event SetPermissionRegistry(address indexed old, address indexed latest);
    event SetGaugeFactory(address indexed old, address indexed latest);
    event SetBribeFor(bool isInternal, address indexed old, address indexed latest, address indexed gauge);
    event SetVoteDelay(uint256 old, uint256 latest);
    event AddFactories(address indexed pairfactory, address indexed gaugefactory);

    constructor() {}

    function initialize(address __ve, address _pairFactory, address  _gaugeFactory, address _bribes) initializer public {
        __Ownable_init();
        __ReentrancyGuard_init();

        _ve = __ve;
        base = IVotingEscrow(__ve).token();

        _factories.push(_pairFactory);
        isFactory[_pairFactory] = true;

        _gaugeFactories.push(_gaugeFactory);
        isGaugeFactory[_gaugeFactory] = true;

        bribefactory = _bribes;

        minter = msg.sender;
        permissionRegistry = msg.sender;

        VOTE_DELAY = 0;
        initflag = false;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    MODIFIERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    modifier VoterAdmin() {
        require(IPermissionsRegistry(permissionRegistry).hasRole("VOTER_ADMIN",msg.sender), 'VOTER_ADMIN');
        _;
    }

    modifier Governance() {
        require(IPermissionsRegistry(permissionRegistry).hasRole("GOVERNANCE",msg.sender), 'GOVERNANCE');
        _;
    }

    /// @notice initialize the voter contract 
    /// @param  _tokens array of tokens to whitelist
    /// @param  _minter the minter of $horiza
    function _init(address[] memory _tokens, address _permissionsRegistry, address _minter) external {
        require(msg.sender == minter || IPermissionsRegistry(permissionRegistry).hasRole("VOTER_ADMIN",msg.sender));
        require(!initflag);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _whitelist(_tokens[i]);
        }
        minter = _minter;
        permissionRegistry = _permissionsRegistry;
        initflag = true;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VoterAdmin
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice set vote delay in seconds
    function setVoteDelay(uint256 _delay) external VoterAdmin {
        require(_delay != VOTE_DELAY, "a");
        require(_delay <= MAX_VOTE_DELAY, "m");
        emit SetVoteDelay(VOTE_DELAY, _delay);
        VOTE_DELAY = _delay;
    }

    /// @notice Set a new Minter
    function setMinter(address _minter) external VoterAdmin {
        emit SetMinter(minter, _minter);
        minter = _minter;
    }

    /// @notice Set a new Bribe Factory
    function setBribeFactory(address _bribeFactory) external VoterAdmin {
        emit SetBribeFactory(bribefactory, _bribeFactory);
        bribefactory = _bribeFactory;
    }


    /// @notice Set a new PermissionRegistry
    function setPermissionsRegistry(address _permissionRegistry) external VoterAdmin {
        emit SetPermissionRegistry(permissionRegistry, _permissionRegistry);
        permissionRegistry = _permissionRegistry;
    }

    /// @notice Set a new bribes for a given gauge
    function setNewBribes(address _gauge, address _internal, address _external) external VoterAdmin {
        require(isGauge[_gauge], "!g");
        _setInternalBribe(_gauge, _internal);
        _setExternalBribe(_gauge, _external);
    }

    /// @notice Set a new internal bribe for a given gauge
    function setInternalBribeFor(address _gauge, address _internal) external VoterAdmin {
        require(isGauge[_gauge], "!g");
        _setInternalBribe(_gauge, _internal);
    }

    /// @notice Set a new External bribe for a given gauge
    function setExternalBribeFor(address _gauge, address _external) external VoterAdmin {
        require(isGauge[_gauge], "!g");
        _setExternalBribe(_gauge, _external);
    }

    function _setInternalBribe(address _gauge, address _internal) private {
        emit SetBribeFor(true, internal_bribes[_gauge], _internal, _gauge);
        internal_bribes[_gauge] = _internal;
    }

    function _setExternalBribe(address _gauge, address _external) private {
        emit SetBribeFor(false, internal_bribes[_gauge], _external, _gauge);
        external_bribes[_gauge] = _external;
    }
    
    function addFactory(address _pairFactory, address _gaugeFactory) external VoterAdmin {
        require(!isFactory[_pairFactory], 'f');
        require(!isGaugeFactory[_gaugeFactory], 'gf');

        _factories.push(_pairFactory);
        _gaugeFactories.push(_gaugeFactory);
        isFactory[_pairFactory] = true;
        isGaugeFactory[_gaugeFactory] = true;
        emit AddFactories(_pairFactory, _gaugeFactory);
    }

    function replaceFactory(address _pairFactory, address _gaugeFactory, uint256 _pos) external VoterAdmin {
        require(isFactory[_pairFactory], '!f');
        require(isGaugeFactory[_gaugeFactory], '!gf');
        address oldPF = _factories[_pos];
        address oldGF = _gaugeFactories[_pos];
        isFactory[oldPF] = false;
        isGaugeFactory[oldGF] = false;

        _factories[_pos] = (_pairFactory);
        _gaugeFactories[_pos] = (_gaugeFactory);
        isFactory[_pairFactory] = true;
        isGaugeFactory[_gaugeFactory] = true;

        emit SetGaugeFactory(oldGF, _gaugeFactory);
        emit SetPairFactory(oldPF, _pairFactory);
    }

    function removeFactory(uint256 _pos) external VoterAdmin {


        address oldPF = _factories[_pos];
        address oldGF = _gaugeFactories[_pos];

        require(isFactory[oldPF], '!f');
        require(isGaugeFactory[oldGF], '!gf');
        _factories[_pos] = address(0);
        _gaugeFactories[_pos] = address(0);
        isFactory[oldPF] = false;
        isGaugeFactory[oldGF] = false;
        emit SetGaugeFactory(oldGF, address(0));
        emit SetPairFactory(oldPF, address(0));
    }
    
    
    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GOVERNANCE
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
    
    
    /// @notice Whitelist a token for gauge creation
    function whitelist(address[] memory _token) external Governance {
        uint256 i = 0;
        for(i = 0; i < _token.length; i++){
            _whitelist(_token[i]);
        }
    }
       
    function _whitelist(address _token) private {
        require(!isWhitelisted[_token], "i");
        require(_token.code.length > 0, "!c");
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }
    
    /// @notice Blacklist a malicious token
    function blacklist(address[] memory _token) external Governance {
        uint256 i = 0;
        for(i = 0; i < _token.length; i++){
            _blacklist(_token[i]);
        }
    }
       
    function _blacklist(address _token) private {
        require(isWhitelisted[_token], "o");
        isWhitelisted[_token] = false;
        emit Blacklisted(msg.sender, _token);
    }

     /// @notice Kill a malicious gauge 
    /// @param  _gauge gauge to kill
    function killGauge(address _gauge) external Governance {
        require(isAlive[_gauge], "k");
        isAlive[_gauge] = false;
        claimable[_gauge] = 0;

        uint _time = _epochTimestamp();
        totalWeightsPerEpoch[_time] -= weightsPerEpoch[_time][poolForGauge[_gauge]]; 


        emit GaugeKilled(_gauge);
    }

    /// @notice Revive a malicious gauge 
    /// @param  _gauge gauge to revive
    function reviveGauge(address _gauge) external Governance {
        require(!isAlive[_gauge], "a");
        require(isGauge[_gauge], 'k');
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    USER INTERACTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    
    /// @notice Reset the votes of a given TokenID
    function reset(uint256 _tokenId) external nonReentrant {
        _voteDelay(_tokenId);
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId), "!ao");
        _reset(_tokenId);
        IVotingEscrow(_ve).abstain(_tokenId);
        lastVoted[_tokenId] = _epochTimestamp() + 1;
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;
        uint256 _time = _epochTimestamp();
        uint256 lastVoteTimestamp = lastVoted[_tokenId];

        for (uint256 i = 0; i < _poolVoteCnt; i ++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {

                votes[_tokenId][_pool] -= _votes;

                // if user last vote is < than epochTimestamp then votes are 0! IF not underflow occur
                if (lastVoteTimestamp > _time) {
                    weightsPerEpoch[_time][_pool] -= _votes;

                    IBribe(internal_bribes[gauges[_pool]]).withdraw(uint256(_votes), _tokenId);
                    IBribe(external_bribes[gauges[_pool]]).withdraw(uint256(_votes), _tokenId);

                    // if is alive remove _votes, else don't because we already done it in killGauge()
                    if(isAlive[gauges[_pool]]) _totalWeight += _votes;
                }
                
                emit Abstained(_tokenId, _votes);
            }
        }

        
        // if user last vote is < than epochTimestamp then _totalWeight is 0! IF not underflow occur
        if(lastVoteTimestamp < _time) _totalWeight = 0;
        
        totalWeightsPerEpoch[_time] -= _totalWeight;
        delete poolVote[_tokenId];
    }

    /// @notice Recast the saved votes of a given TokenID
    function poke(uint256 _tokenId) external nonReentrant {
        _voteDelay(_tokenId);
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId), "!ao");
        address[] memory _poolVote = poolVote[_tokenId];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; i ++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
        lastVoted[_tokenId] = _epochTimestamp() + 1;
    }

    
    /// @notice Vote for pools
    /// @param  _tokenId    veNFT tokenID used to vote
    /// @param  _poolVote   array of LPs addresses to vote  (eg.: [sAMM usdc-usdt   , sAMM busd-usdt, vAMM wbnb-the ,...])
    /// @param  _weights    array of weights for each LPs   (eg.: [10               , 90            , 45             ,...])  
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external nonReentrant {
        _voteDelay(_tokenId);
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId), "!ao");
        require(_poolVote.length == _weights.length, "pw");
        _vote(_tokenId, _poolVote, _weights);
        lastVoted[_tokenId] = _epochTimestamp() + 1;
    }
    
    function _vote(uint256 _tokenId, address[] memory _poolVote, uint256[] memory _weights) internal {
        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(_ve).balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;
        uint256 _time = _epochTimestamp();



        for (uint i = 0; i < _poolCnt; i++) {

            if(isAlive[gauges[_poolVote[i]]]) _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge] && isAlive[_gauge]) {
                uint256 _poolWeight = _weights[i] * _weight / _totalVoteWeight;

                require(votes[_tokenId][_pool] == 0);
                require(_poolWeight != 0);

                poolVote[_tokenId].push(_pool);
                weightsPerEpoch[_time][_pool] += _poolWeight;

                votes[_tokenId][_pool] += _poolWeight;

                IBribe(internal_bribes[_gauge]).deposit(uint256(_poolWeight), _tokenId);
                IBribe(external_bribes[_gauge]).deposit(uint256(_poolWeight), _tokenId);
                
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) IVotingEscrow(_ve).voting(_tokenId);
        totalWeightsPerEpoch[_time] += _totalWeight;
    }

    /// @notice claim LP gauge rewards
    function claimRewards(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(msg.sender);
        }
    }

    /// @notice claim bribes rewards given a TokenID
    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId), "!ao");
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    /// @notice claim fees rewards given a TokenID
    function claimFees(address[] memory _fees, address[][] memory _tokens, uint256 _tokenId) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId), "!ao");
        for (uint256 i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    /// @notice claim bribes rewards given an address
    function claimBribes(address[] memory _bribes, address[][] memory _tokens) external {
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForAddress(msg.sender, _tokens[i]);
        }
    }

    /// @notice claim fees rewards given an address
    function claimFees(address[] memory _bribes, address[][] memory _tokens) external {
        for (uint256 i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForAddress(msg.sender, _tokens[i]);
        }
    }    

  
    /// @notice check if user can vote
    function _voteDelay(uint256 _tokenId) internal view {
        if(lastVoted[_tokenId] > _epochTimestamp()){
            // revote
            require(block.timestamp > lastVoted[_tokenId] + VOTE_DELAY, "d");
        }
    }



     /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    GAUGE CREATION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
    /// @notice create multiple gauges
    function createGauges(address[] memory _pool, uint256[] memory _gaugeTypes) external nonReentrant returns(address[] memory, address[] memory, address[] memory)  {
        require(_pool.length == _gaugeTypes.length, "l");
        require(_pool.length <= 10, "10");
        address[] memory _gauge = new address[](_pool.length);
        address[] memory _int = new address[](_pool.length);
        address[] memory _ext = new address[](_pool.length);

        uint256 i = 0;
        for(i; i < _pool.length; i++){
            (_gauge[i], _int[i], _ext[i]) = _createGauge(_pool[i], _gaugeTypes[i]);
        }
        return (_gauge, _int, _ext);
    }

     /// @notice create a gauge  
    function createGauge(address _pool, uint256 _gaugeType) external nonReentrant returns (address _gauge, address _internal_bribe, address _external_bribe)  {
        (_gauge, _internal_bribe, _external_bribe) = _createGauge(_pool, _gaugeType);
    }

    function append(string memory a, string memory b, string memory c, string memory d, string memory e, string memory f) internal pure returns (string memory) {

        return string(abi.encodePacked(a, b, c, d, e, f));

    }

    /// @notice create a gauge
    /// @param  _pool       LP address 
    /// @param  _gaugeType  the type of the gauge you want to create
    /// @dev    To create stable/Volatile pair gaugeType = 0, Concentrated liqudity = 1, ...
    ///         Make sure to use the corrcet gaugeType or it will fail

    function _createGauge(address _pool, uint256 _gaugeType) internal returns (address _gauge, address _internal_bribe, address _external_bribe) {
        require(_gaugeType < _factories.length, "gt");
        require(gauges[_pool] == address(0x0), "!e");
        require(_pool.code.length > 0, "!c");

        bool isPair;
        address _factory = _factories[_gaugeType];
        require(_factory != address(0), "a");
        require(_gaugeFactories[_gaugeType] != address(0), "a");
        

        address tokenA = address(0);
        address tokenB = address(0);
        (tokenA) = IPairInfo(_pool).token0();
        (tokenB) = IPairInfo(_pool).token1();
        uint24 _fee = IPairInfo(_pool).fee();

        // for future implementation add isPair() in factory
        if(_gaugeType == 0){
            isPair = IPairFactory(_factory).isPair(_pool);
        } 
        if(_gaugeType == 1) {
            address _pool_factory = IUniV3Factory(_factory).getPool(tokenA, tokenB, _fee);
            require(_pool == _pool_factory, 'wrong tokens');    
            isPair = true;
        } else {
            //update
            //isPair = false;
        }

        // gov can create for any pool, even non-Horiza pairs
        if (!IPermissionsRegistry(permissionRegistry).hasRole("GOVERNANCE",msg.sender)) { 
            require(isPair, "!p");
            require(isWhitelisted[tokenA] && isWhitelisted[tokenB], "!w");
            require(tokenA != address(0) && tokenB != address(0), "!pt");
        }

        // create internal and external bribe
        address _owner = IPermissionsRegistry(permissionRegistry).horizaTeamMultisig();
        string memory _type =  append("Horiza LP Fees: ", IERC20(tokenA).symbol(), "-", IERC20(tokenB).symbol(), "-", Strings.toString(_fee));
        _internal_bribe = IBribeFactory(bribefactory).createBribe(_owner, tokenA, tokenB, _type);

        _type = append("Horiza Bribes: ", IERC20(tokenA).symbol(), "-", IERC20(tokenB).symbol(), "-", Strings.toString(_fee));
        _external_bribe = IBribeFactory(bribefactory).createBribe(_owner, tokenA, tokenB, _type);
        
        //biba
        // create gauge
        _gauge = IGaugeFactory(_gaugeFactories[_gaugeType]).createGaugeV2(base, _ve, _pool, address(this), _internal_bribe, _external_bribe, isPair);
     
        // approve spending for $horiza
        IERC20(base).approve(_gauge, type(uint256).max);

        // save data
        internal_bribes[_gauge] = _internal_bribe;
        external_bribes[_gauge] = _external_bribe;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        pools.push(_pool);

        // update index
        supplyIndex[_gauge] = index; // new gauges are set to the default global state

        emit GaugeCreated(_gauge, msg.sender, _internal_bribe, _external_bribe, _pool);
    }

   
    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    VIEW FUNCTIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice view the total length of the pools
    function length() external view returns (uint256) {
        return pools.length;
    }

    /// @notice view the total length of the voted pools given a tokenId
    function poolVoteLength(uint256 tokenId) external view returns(uint256) { 
        return poolVote[tokenId].length;
    }

    function factories() external view returns(address[] memory){
        return _factories;
    }
    
    function factoryLength() external view returns(uint256){
        return _factories.length;
    }
    
    function gaugeFactories() external view returns(address[] memory){
        return _gaugeFactories;
    }
    
    function gaugeFactoriesLength() external view returns(uint256) {
        return _gaugeFactories.length;
    }

    function weights(address _pool) public view returns(uint256) {
        uint256 _time = _epochTimestamp();
        return weightsPerEpoch[_time][_pool];
    }

    function weightsAt(address _pool, uint256 _time) public view returns(uint256) {
        return weightsPerEpoch[_time][_pool];
    }

    function totalWeight() public view returns(uint256) {
        uint256 _time = _epochTimestamp();
        return totalWeightsPerEpoch[_time];
    }

    function totalWeightAt(uint256 _time) public view returns(uint256) {
        return totalWeightsPerEpoch[_time];
    }

    function _epochTimestamp() public view returns(uint256) {
        return IMinter(minter).active_period();
    }
    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /// @notice notify reward amount for gauge
    /// @dev    the function is called by the minter each epoch. Anyway anyone can top up some extra rewards.
    /// @param  amount  amount to distribute
    function notifyRewardAmount(uint256 amount) external {
        require(msg.sender == minter, "!m");
        IERC20Upgradeable(base).safeTransferFrom(msg.sender, address(this), amount);


        uint256 _totalWeight = totalWeightAt(_epochTimestamp() - 1 weeks);   // minter call notify after updates active_period, loads votes - 1 week

        uint256 _ratio = 0;

        if(_totalWeight > 0) _ratio = amount * 1e18 / _totalWeight;     // 1e18 adjustment is removed during claim
        if (_ratio > 0) {
            index += _ratio;
        }

        emit NotifyReward(msg.sender, base, amount);
    }


    /// @notice distribute the LP Fees to the internal bribes
    /// @param  _gauges  gauge address where to claim the fees 
    /// @dev    the gauge is the owner of the LPs so it has to claim
    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            if (isGauge[_gauges[i]] && isAlive[_gauges[i]]){
                IGauge(_gauges[i]).claimFees();
            }
        }
    }

    
    /// @notice Distribute the emission for ALL gauges 
    function distributeAll() external nonReentrant {
        IMinter(minter).update_period();

        uint256 x = 0;
        uint256 stop = pools.length;
        for (x; x < stop; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    /// @notice distribute the emission for N gauges
    /// @param  start   start index point of the pools array
    /// @param  finish  finish index point of the pools array
    /// @dev    this function is used in case we have too many pools and gasLimit is reached
    function distribute(uint256 start, uint256 finish) public nonReentrant {
        IMinter(minter).update_period();
        for (uint256 x = start; x < finish; x++) {
            _distribute(gauges[pools[x]]);
        }
    }

    /// @notice distribute reward onyl for given gauges
    /// @dev    this function is used in case some distribution fails
    function distribute(address[] memory _gauges) external nonReentrant {
        IMinter(minter).update_period();
        for (uint256 x = 0; x < _gauges.length; x++) {
            _distribute(_gauges[x]);
        }
    }

    /// @notice distribute the emission
    function _distribute(address _gauge) internal {

        uint256 lastTimestamp = gaugesDistributionTimestmap[_gauge];
        uint256 currentTimestamp = _epochTimestamp();
        if(lastTimestamp < currentTimestamp){
            _updateForAfterDistribution(_gauge); // should set claimable to 0 if killed

            uint256 _claimable = claimable[_gauge];

            // distribute only if claimable is > 0, currentEpoch != lastepoch and gauge is alive
            if (_claimable > 0 && isAlive[_gauge]) {
                claimable[_gauge] = 0;
                gaugesDistributionTimestmap[_gauge] = currentTimestamp;
                IGauge(_gauge).notifyRewardAmount(base, _claimable);
                emit DistributeReward(msg.sender, _gauge, _claimable);
            }
        }
    }


    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    HELPERS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
 
  
    /// @notice update info for gauges
    /// @dev    this function track the gauge index to emit the correct $horiza amount after the distribution
    function _updateForAfterDistribution(address _gauge) private {
        address _pool = poolForGauge[_gauge];
        uint256 _time = _epochTimestamp() - 604800;
        uint256 _supplied = weightsPerEpoch[_time][_pool];

        if (_supplied > 0) {
            uint256 _supplyIndex = supplyIndex[_gauge];
            uint256 _index = index; // get global index0 for accumulated distro
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0) {
                uint256 _share = _supplied * _delta / 1e18; // add accrued difference for each supplied token
                if (isAlive[_gauge]) {
                    claimable[_gauge] += _share;
                }
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }
    
}

