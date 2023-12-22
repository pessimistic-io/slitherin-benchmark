// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./Initializable.sol";
import "./Math.sol";
import "./ERC1967Upgrade.sol";

import "./IFeeDistributor.sol";
import "./IFeeDistributorFactory.sol";
import "./IGauge.sol";
import "./IGaugeFactory.sol";
import "./IERC20.sol";
import "./IMinter.sol";
import "./IPair.sol";
import "./IPairFactory.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";
import "./IXRam.sol";

import "./IRamsesV2Factory.sol";
import "./IRamsesV2GaugeFactory.sol";
import "./INonfungiblePositionManager.sol";
import "./IRamsesV2PoolOwnerActions.sol";

contract Voter is IVoter, Initializable, ERC1967Upgrade {
    address public _ve; // the ve token that governs these contracts
    address public factory; // the PairFactory
    address public base;
    address public gaugefactory;
    address public feeDistributorFactory;
    uint256 internal constant DURATION = 7 days; // rewards are released over 7 days
    address public minter;
    address public governor; // should be set to an IGovernor
    address public emergencyCouncil; // credibly neutral party similar to Curve's Emergency DAO

    uint256 public totalWeight; // total voting weight

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public poolForGauge; // gauge => pool
    mapping(address => address) public feeDistributers; // gauge => internal bribe (only fees)
    mapping(address => uint256) public weights; // pool => weight
    mapping(uint256 => mapping(address => uint256)) public votes; // nft => pool => votes
    mapping(uint256 => address[]) public poolVote; // nft => pools
    mapping(uint256 => uint256) public usedWeights; // nft => total voting weight of user
    mapping(uint256 => uint256) public lastVoted; // nft => timestamp of last vote, to ensure one vote per epoch
    mapping(address => bool) public isGauge;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isAlive;

    uint256 internal _unlocked;

    uint256 internal index;
    mapping(address => uint256) internal supplyIndex;
    mapping(address => uint256) public claimable;

    // Initialize version 2 - CL pools
    address public clFactory;
    address public clGaugeFactory;
    address public nfpManager;

    // Initialize version 3 - xRam
    IXRam public xRam;
    address public xWhitelistOperator;
    uint256 public constant BASIS = 10000;
    uint256 public xRamRatio; // default xRam ratio
    mapping(address => uint256) _gaugeXRamRatio; // mapping for specific gauge xRam ratios
    mapping(address => bool) _gaugeXRamRatioWritten; // mapping for indicating if a gauge has its own xRam ratio

    // v3.1 Forbid
    // @dev no initialization needed
    mapping(address => bool) public isForbidden;
    // v3.2
    mapping(uint256 => bool) public partnerNFT;
    mapping(uint256 => bool) public stale;

    // End of storage slots //

    ////////////
    // Events //
    ////////////

    event GaugeCreated(
        address indexed gauge,
        address creator,
        address feeDistributer,
        address indexed pool
    );
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Voted(address indexed voter, uint256 tokenId, uint256 weight);
    event Abstained(uint256 tokenId, uint256 weight);
    event Deposit(
        address indexed lp,
        address indexed gauge,
        uint256 tokenId,
        uint256 amount
    );
    event Withdraw(
        address indexed lp,
        address indexed gauge,
        uint256 tokenId,
        uint256 amount
    );
    event NotifyReward(
        address indexed sender,
        address indexed reward,
        uint256 amount
    );
    event DistributeReward(
        address indexed sender,
        address indexed gauge,
        uint256 amount
    );
    event Attach(address indexed owner, address indexed gauge, uint256 tokenId);
    event Detach(address indexed owner, address indexed gauge, uint256 tokenId);
    event Whitelisted(address indexed whitelister, address indexed token);
    event Forbidden(
        address indexed forbidder,
        address indexed token,
        bool status
    );

    event XRamRatio(address indexed gauge, uint256 oldRatio, uint256 newRatio);

    //////////////////
    // Initializers //
    //////////////////

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Returns the initializer version
    function initializedVersion() external view returns (uint8) {
        return _getInitializedVersion();
    }

    function initialize(
        address __ve,
        address _factory,
        address _gauges,
        address _feeDistributorFactory,
        address _minter,
        address _msig,
        address[] memory _tokens
    ) external initializer {
        _ve = __ve;
        factory = _factory;
        base = IVotingEscrow(__ve).token();
        gaugefactory = _gauges;
        feeDistributorFactory = _feeDistributorFactory;
        minter = _minter;
        governor = _msig;
        emergencyCouncil = _msig;

        for (uint256 i = 0; i < _tokens.length; ++i) {
            _whitelist(_tokens[i]);
        }

        _unlocked = 1;
        index = 1;
    }

    /// @notice Initializes the Voter with CL contracts
    function initializeCl(
        address _clFactory,
        address _clGaugeFactory,
        address _nfpManager
    ) external reinitializer(2) {
        require(msg.sender == governor || msg.sender == _getAdmin());

        clFactory = _clFactory;
        clGaugeFactory = _clGaugeFactory;
        nfpManager = _nfpManager;
    }

    /// @notice Initializes xRam, emission ratios, and approvals after the upgrade
    function initializeXRam(address _xRam) external reinitializer(3) {
        require(msg.sender == governor || msg.sender == _getAdmin());

        // set xRam
        xRam = IXRam(_xRam);

        // set emission ratio
        xRamRatio = 5000;
        emit XRamRatio(address(0), 0, 5000);

        // approve xRam to spend Ram
        IERC20(base).approve(address(_xRam), type(uint256).max);

        // approve all gauges to spend xRam
        // only possible on Arbitrum, this block isn't needed for fresh deployments
        uint256 _length = pools.length;
        for (uint256 i = 0; i < _length; ++i) {
            address _gauge = gauges[pools[i]];

            IXRam(_xRam).approve(_gauge, type(uint256).max);
        }
    }

    ///////////////
    // Modifiers //
    ///////////////

    // simple re-entrancy check
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure minter is synced
        require(
            block.timestamp < IMinter(minter).active_period() + 1 weeks,
            "UPDATE_PERIOD"
        );
        _;
    }

    modifier onlyTimelock() {
        require(
            msg.sender == 0x9314fC5633329d285F744108D637E1222CEbae1c,
            "!admin"
        );
        _;
    }

    modifier onlyWhitelistOperators() {
        require(
            msg.sender == xWhitelistOperator || msg.sender == governor,
            "auth"
        );
        _;
    }

    ////////////////////////////////
    // Governance Gated Functions //
    ////////////////////////////////

    function setGovernor(address _governor) public {
        require(msg.sender == governor);
        governor = _governor;
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == emergencyCouncil);
        emergencyCouncil = _council;
    }

    function setXWhitelistOperator(address _xWhitelistOperator) public {
        require(msg.sender == governor);
        xWhitelistOperator = _xWhitelistOperator;
    }

    /// @notice sets the default xRamRatio
    function setXRamRatio(uint256 _xRamRatio) external onlyWhitelistOperators {
        require(_xRamRatio <= BASIS, ">100%");

        emit XRamRatio(address(0), xRamRatio, _xRamRatio);
        xRamRatio = _xRamRatio;
    }

    /// @notice sets the xRamRatio of specifics gauges
    function setGaugeXRamRatio(
        address[] calldata _gauges,
        uint256[] calldata _xRamRatios
    ) external onlyWhitelistOperators {
        uint256 _length = _gauges.length;
        require(_length == _xRamRatios.length, "length mismatch");

        for (uint256 i = 0; i < _length; ++i) {
            uint256 _xRamRatio = _xRamRatios[i];
            require(_xRamRatio <= BASIS, ">100%");

            // fetch old xRam ratio for later event
            address _gauge = _gauges[i];
            uint256 oldXRamRatio = gaugeXRamRatio(_gauge);

            // write gauge specific xRam ratio
            _gaugeXRamRatio[_gauge] = _xRamRatio;
            _gaugeXRamRatioWritten[_gauge] = true;

            emit XRamRatio(_gauge, oldXRamRatio, _xRamRatio);
        }
    }

    /// @notice resets the xRamRatio of specifics gauges back to default
    function resetGaugeXRamRatio(
        address[] calldata _gauges
    ) external onlyWhitelistOperators {
        uint256 _xRamRatio = xRamRatio;
        uint256 _length = _gauges.length;
        for (uint256 i = 0; i < _length; ++i) {
            // fetch old xRam ratio for later event
            address _gauge = _gauges[i];
            uint256 oldXRamRatio = gaugeXRamRatio(_gauge);

            // reset _gaugeXRamRatioWritten
            _gaugeXRamRatioWritten[_gauge] = false;
            // it's ok to leave _gaugeXRamRatio dirty, it's going to be overwriten when it's activated again

            emit XRamRatio(_gauge, oldXRamRatio, _xRamRatio);
        }
    }

    function whitelist(address _token) public onlyWhitelistOperators {
        _whitelist(_token);
    }

    function forbid(
        address _token,
        bool _status
    ) public onlyWhitelistOperators {
        _forbid(_token, _status);
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token]);
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }

    function _forbid(address _token, bool _status) internal {
        // forbid can happen before whitelisting
        if (isForbidden[_token] != _status) {
            isForbidden[_token] = _status;
            emit Forbidden(msg.sender, _token, _status);
        }
    }

    function killGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    function whitelistGaugeRewards(
        address[] calldata _gauges,
        address[] calldata _rewards
    ) external onlyWhitelistOperators {
        uint256 len = _gauges.length;
        for (uint256 i; i < len; ++i) {
            IGauge(_gauges[i]).whitelistNotifiedRewards(_rewards[i]);
        }
    }

    function removeGaugeRewards(
        address[] calldata _gauges,
        address[] calldata _rewards
    ) external onlyWhitelistOperators {
        uint256 len = _gauges.length;
        for (uint256 i; i < len; ++i) {
            IGauge(_gauges[i]).removeRewardWhitelist(_rewards[i]);
        }
    }

    ////////////
    // Voting //
    ////////////

    function reset(uint256 _tokenId) external onlyNewEpoch(_tokenId) {
        require(
            IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId) ||
                IVotingEscrow(_ve).isDelegate(msg.sender, _tokenId),
            "!approved"
        );
        lastVoted[_tokenId] = (block.timestamp / DURATION) * DURATION;
        _reset(_tokenId);
        IVotingEscrow(_ve).abstain(_tokenId);
    }

    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; ++i) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                _updateFor(gauges[_pool]);
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                if (_votes > 0) {
                    IFeeDistributor(feeDistributers[gauges[_pool]])._withdraw(
                        uint256(_votes),
                        _tokenId
                    );
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

    function poke(uint256 _tokenId) external {
        address[] memory _poolVote = poolVote[_tokenId];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; ++i) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }

    function _vote(
        uint256 _tokenId,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        require(!stale[_tokenId], "Stale NFT, please contact the team");

        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(_ve).balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; ++i) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; ++i) {
            address _pool = _poolVote[i];
            address _gauge = gauges[_pool];

            if (isGauge[_gauge] && isAlive[_gauge]) {
                uint256 _poolWeight = (_weights[i] * _weight) /
                    _totalVoteWeight;
                require(votes[_tokenId][_pool] == 0);
                require(_poolWeight != 0);
                _updateFor(_gauge);

                poolVote[_tokenId].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_tokenId][_pool] += _poolWeight;
                IFeeDistributor(feeDistributers[_gauge])._deposit(
                    uint256(_poolWeight),
                    _tokenId
                );
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) IVotingEscrow(_ve).voting(_tokenId);
        totalWeight += uint256(_totalWeight);
        usedWeights[_tokenId] = uint256(_usedWeight);
    }

    function vote(
        uint256 tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(tokenId) {
        require(
            IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, tokenId) ||
                IVotingEscrow(_ve).isDelegate(msg.sender, tokenId),
            "!approved"
        );
        require(_poolVote.length == _weights.length);
        lastVoted[tokenId] = (block.timestamp / DURATION) * DURATION;
        _vote(tokenId, _poolVote, _weights);
    }

    ////////////////////
    // Gauge Creation //
    ////////////////////
    function createGauge(address _pool) external returns (address) {
        require(gauges[_pool] == address(0x0), "exists");
        address[] memory allowedRewards = new address[](3);
        address[] memory internalRewards = new address[](2);
        bool isPair = IPairFactory(factory).isPair(_pool);
        address tokenA;
        address tokenB;

        if (isPair) {
            (tokenA, tokenB) = IPair(_pool).tokens();
            allowedRewards[0] = tokenA;
            allowedRewards[1] = tokenB;
            internalRewards[0] = tokenA;
            internalRewards[1] = tokenB;

            if (base != tokenA && base != tokenB) {
                allowedRewards[2] = base;
            }
        }

        if (msg.sender != governor) {
            // gov can create for any pool, even non-Ramses pairs
            require(isPair, "!_pool");
            // prevent gauge creation for forbidden tokens
            require(!isForbidden[tokenA] && !isForbidden[tokenB], "Forbidden");
            require(
                isWhitelisted[tokenA] && isWhitelisted[tokenB],
                "!whitelisted"
            );
        }

        address _feeDistributer = IFeeDistributorFactory(feeDistributorFactory)
            .createFeeDistributor(_pool);
        // return address(0);
        address _gauge = IGaugeFactory(gaugefactory).createGauge(
            _pool,
            _feeDistributer,
            _ve,
            isPair,
            allowedRewards
        );

        IERC20(base).approve(_gauge, type(uint256).max);
        xRam.approve(_gauge, type(uint256).max);
        feeDistributers[_gauge] = _feeDistributer;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        _updateFor(_gauge);
        pools.push(_pool);
        emit GaugeCreated(_gauge, msg.sender, _feeDistributer, _pool);
        return _gauge;
    }

    function createCLGauge(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address) {
        address _pool = IRamsesV2Factory(clFactory).getPool(
            tokenA,
            tokenB,
            fee
        );
        require(_pool != address(0), "no pool");
        require(gauges[_pool] == address(0x0), "exists");

        if (msg.sender != governor) {
            // gov can create for any cl pool, even non-Ramses pairs
            // for arbitrary gauges without a pool, use createGauge()

            // prevent gauge creation for forbidden tokens
            require(!isForbidden[tokenA] && !isForbidden[tokenB], "Forbidden");
            require(
                isWhitelisted[tokenA] && isWhitelisted[tokenB],
                "!whitelisted"
            );
        }

        address _feeDistributer = IFeeDistributorFactory(feeDistributorFactory)
            .createFeeDistributor(_pool);
        // return address(0);
        address _gauge = IRamsesV2GaugeFactory(clGaugeFactory).createGauge(
            _pool
        );

        IERC20(base).approve(_gauge, type(uint256).max);
        xRam.approve(_gauge, type(uint256).max);
        feeDistributers[_gauge] = _feeDistributer;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        _updateFor(_gauge);
        pools.push(_pool);

        IRamsesV2PoolOwnerActions(_pool).setFeeProtocol();

        emit GaugeCreated(_gauge, msg.sender, _feeDistributer, _pool);
        return _gauge;
    }

    ///@dev designates a partner veNFT as stale
    function designateStale(uint256 _tokenId, bool _status) external {
        require(msg.sender == governor, "!GOV");
        require(partnerNFT[_tokenId] == true, "!P");
        stale[_tokenId] = _status;
        _reset(_tokenId);
    }

    ///@dev designates a veNFT as a partner veNFT
    function designatePartnerNFT(uint256 _tokenId, bool _status) external {
        require(msg.sender == governor, "!GOV");
        if (!_status && stale[_tokenId]) {
            stale[_tokenId] = false;
        }
        partnerNFT[_tokenId] = _status;
    }

    ///@dev in case of emission stuck due to killed gauges and unsupported operations
    function stuckEmissionsRecovery(address _gauge) external {
        require(msg.sender == governor, "!GOV");

        IMinter(minter).update_period();
        _updateFor(_gauge);

        if (!isAlive[_gauge]) {
            uint256 _claimable = claimable[_gauge];
            delete claimable[_gauge];
            if (_claimable > 0) {
                IERC20(base).transfer(governor, _claimable);
            }
        }
    }

    ////////////////////
    // Event Emitters //
    ////////////////////
    function attachTokenToGauge(uint256 tokenId, address account) external {
        require(isGauge[msg.sender] || isGauge[gauges[msg.sender]]);
        require(isAlive[msg.sender] || isGauge[gauges[msg.sender]]); // killed gauges cannot attach tokens to themselves
        if (tokenId > 0) IVotingEscrow(_ve).attach(tokenId);
        emit Attach(account, msg.sender, tokenId);
    }

    function emitDeposit(
        uint256 tokenId,
        address account,
        uint256 amount
    ) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]);
        emit Deposit(account, msg.sender, tokenId, amount);
    }

    function detachTokenFromGauge(uint256 tokenId, address account) external {
        require(isGauge[msg.sender] || isGauge[gauges[msg.sender]]);
        if (tokenId > 0) IVotingEscrow(_ve).detach(tokenId);
        emit Detach(account, msg.sender, tokenId);
    }

    function emitWithdraw(
        uint256 tokenId,
        address account,
        uint256 amount
    ) external {
        require(isGauge[msg.sender]);
        emit Withdraw(account, msg.sender, tokenId, amount);
    }

    /////////////////////////////
    // One-stop Reward Claimer //
    /////////////////////////////

    function claimClGaugeRewards(
        address[] calldata _gauges,
        address[][] calldata _tokens,
        uint256[][] calldata _nfpTokenIds
    ) external {
        address _nfpManager = nfpManager;
        for (uint256 i = 0; i < _gauges.length; ++i) {
            for (uint256 j = 0; j < _nfpTokenIds[i].length; ++j) {
                require(
                    msg.sender ==
                        INonfungiblePositionManager(_nfpManager).ownerOf(
                            _nfpTokenIds[i][j]
                        ) ||
                        msg.sender ==
                        INonfungiblePositionManager(_nfpManager).getApproved(
                            _nfpTokenIds[i][j]
                        )
                );
                IFeeDistributor(_gauges[i]).getRewardForOwner(
                    _nfpTokenIds[i][j],
                    _tokens[i]
                );
            }
        }
    }

    function claimBribes(
        address[] memory _bribes,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
        for (uint256 i = 0; i < _bribes.length; ++i) {
            IFeeDistributor(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
        for (uint256 i = 0; i < _fees.length; ++i) {
            IFeeDistributor(_fees[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    function claimRewards(
        address[] memory _gauges,
        address[][] memory _tokens
    ) external {
        for (uint256 i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(msg.sender, _tokens[i]);
        }
    }

    //////////////////////////
    // Emission Calculation //
    //////////////////////////

    function notifyRewardAmount(uint256 amount) external {
        if (totalWeight > 0) {
            _safeTransferFrom(base, msg.sender, address(this), amount); // transfer the distro in
            uint256 _ratio = (amount * 1e18) / totalWeight; // 1e18 adjustment is removed during claim
            if (_ratio > 0) {
                index += _ratio;
            }
            emit NotifyReward(msg.sender, base, amount);
        }
    }

    function updateFor(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; ++i) {
            _updateFor(_gauges[i]);
        }
    }

    function updateForRange(uint256 start, uint256 end) public {
        for (uint256 i = start; i < end; ++i) {
            _updateFor(gauges[pools[i]]);
        }
    }

    function updateAll() external {
        updateForRange(0, pools.length);
    }

    function updateGauge(address _gauge) external {
        _updateFor(_gauge);
    }

    function _updateFor(address _gauge) internal {
        address _pool = poolForGauge[_gauge];
        uint256 _supplied = weights[_pool];
        uint256 _supplyIndex = supplyIndex[_gauge];

        // only new pools will have 0 _supplyIndex
        if (_supplyIndex > 0) {
            uint256 _index = index; // get global index0 for accumulated distro
            supplyIndex[_gauge] = _index; // update _gauge current position to global position
            uint256 _delta = _index - _supplyIndex; // see if there is any difference that need to be accrued
            if (_delta > 0 && _supplied > 0) {
                uint256 _share = (uint256(_supplied) * _delta) / 1e18; // add accrued difference for each supplied token
                claimable[_gauge] += _share;
            }
        } else {
            supplyIndex[_gauge] = index; // new users are set to the default global state
        }
    }

    ///////////////////////////
    // Emission Distribution //
    ///////////////////////////

    function distributeFees(address[] memory _gauges) external {
        for (uint256 i = 0; i < _gauges.length; ++i) {
            if (IGauge(_gauges[i]).isForPair()) {
                IGauge(_gauges[i]).claimFees();
            }
        }
    }

    function distribute(address _gauge) public lock {
        IMinter(minter).update_period();
        _updateFor(_gauge);

        // dead gauges should be handled by a different function
        if (isAlive[_gauge]) {
            uint256 _claimable = claimable[_gauge];

            if (_claimable == 0) {
                return;
            }

            // calculate _xRamClaimable
            address _xRam = address(xRam);
            uint256 _xRamClaimable = (_claimable * gaugeXRamRatio(_gauge)) /
                BASIS;
            _claimable -= _xRamClaimable;

            // can only distribute if the distributed amount / week > 0 and is > left()
            bool canDistribute = true;

            // _claimable could be 0 if emission is 100% xRAM
            if (_claimable > 0) {
                if (
                    _claimable / DURATION == 0 ||
                    _claimable < IGauge(_gauge).left(base)
                ) {
                    canDistribute = false;
                }
            }
            // _xRamClaimable could be 0 if emission is 100% RAM
            if (_xRamClaimable > 0) {
                if (
                    _xRamClaimable / DURATION == 0 ||
                    _xRamClaimable < IGauge(_gauge).left(_xRam)
                ) {
                    canDistribute = false;
                }
            }

            if (canDistribute) {
                // reset claimable
                claimable[_gauge] = 0;

                if (_claimable > 0) {
                    // notify RAM
                    IGauge(_gauge).notifyRewardAmount(base, _claimable);
                }

                if (_xRamClaimable > 0) {
                    // convert, then notify xRAM
                    IXRam(_xRam).convertRam(_xRamClaimable);
                    IGauge(_gauge).notifyRewardAmount(_xRam, _xRamClaimable);
                }

                emit DistributeReward(
                    msg.sender,
                    _gauge,
                    _claimable + _xRamClaimable
                );
            }
        }
    }

    function distro() external {
        distribute(0, pools.length);
    }

    function distribute() external {
        distribute(0, pools.length);
    }

    function distribute(uint256 start, uint256 finish) public {
        for (uint256 x = start; x < finish; x++) {
            distribute(gauges[pools[x]]);
        }
    }

    function distribute(address[] memory _gauges) external {
        for (uint256 x = 0; x < _gauges.length; x++) {
            distribute(_gauges[x]);
        }
    }

    ////////////////////
    // View Functions //
    ////////////////////
    function length() external view returns (uint256) {
        return pools.length;
    }

    function getVotes(
        uint256 fromTokenId,
        uint256 toTokenId
    )
        external
        view
        returns (
            address[][] memory tokensVotes,
            uint256[][] memory tokensWeights
        )
    {
        uint256 tokensCount = toTokenId - fromTokenId + 1;
        tokensVotes = new address[][](tokensCount);
        tokensWeights = new uint256[][](tokensCount);
        for (uint256 i = 0; i < tokensCount; ++i) {
            uint256 tokenId = fromTokenId + i;
            tokensVotes[i] = new address[](poolVote[tokenId].length);
            tokensVotes[i] = poolVote[tokenId];

            tokensWeights[i] = new uint256[](poolVote[tokenId].length);
            for (uint256 j = 0; j < tokensVotes[i].length; ++j) {
                tokensWeights[i][j] = votes[tokenId][tokensVotes[i][j]];
            }
        }
    }

    /// @notice returns the xRamRatio applicable to a gauge
    /// @dev for default ratios, call this with address(0) or call xRamRatio
    function gaugeXRamRatio(address gauge) public view returns (uint256) {
        // return gauge specific xRam Ratio if writter
        if (_gaugeXRamRatioWritten[gauge]) {
            return _gaugeXRamRatio[gauge];
        }

        // otherwise return default xRamRatio
        return xRamRatio;
    }

    //////////////////////
    // safeTransferFrom //
    //////////////////////

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

