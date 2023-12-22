// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Math.sol";
import "./IBribe.sol";
import "./IBribeFactory.sol";
import "./IGauge.sol";
import "./IGaugeFactory.sol";
import "./IERC20.sol";
import "./IPair.sol";
import "./IPairFactory.sol";
import "./IVotingEscrow.sol";
import "./NonblockingLzApp.sol";
import "./console.sol";

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IOFT {
    function mintWeeklyRewards(address _toAddress, uint _amount) external;
}

contract VoterV2_1 is NonblockingLzApp, ReentrancyGuard {

    uint16 public constant SRC_CHAIN_ID = 56; // bsc

    uint public active_period;

    address public _ve; // the ve token that governs these contracts
    address public factory; // the PairFactory
    address internal base;
    address public gaugefactory;
    address public bribefactory;
    uint internal constant DURATION = 7 days; // rewards are released over 7 days
    address public governor; // should be set to an IGovernor
    address public emergencyCouncil; // credibly neutral party similar to Curve's Emergency DAO

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public gauges; // pool => gauge
    mapping(address => address) public mainChainGauges; // mainGauge => sideGauge
    mapping(address => uint) public gaugesDistributionTimestmap;
    mapping(address => address) public poolForGauge; // gauge => pool
    mapping(address => address) public internal_bribes; // gauge => internal bribe (only fees)
    mapping(address => address) public external_bribes; // gauge => external bribe (real bribes)
    mapping(address => bool) public isGauge;
    mapping(address => bool) public isAlive;

    mapping(uint256 => mapping(address => uint256)) public availableEmissions; // epoch => mainGauge => emissions
    bool public lzOneStepProcess = true; // whether nonblockingLzReceive also distributes or not

    event GaugeCreated(address indexed gauge, address creator, address internal_bribe, address indexed external_bribe, address indexed pool);
    event GaugeKilled(address indexed gauge);
    event GaugeRevived(address indexed gauge);
    event Deposit(address indexed lp, address indexed gauge, uint tokenId, uint amount);
    event Withdraw(address indexed lp, address indexed gauge, uint tokenId, uint amount);
    event NotifyReward(address indexed sender, address indexed reward, uint amount);
    event DistributeReward(address indexed sender, address indexed gauge, uint amount);
    event Attach(address indexed owner, address indexed gauge, uint tokenId);
    event Detach(address indexed owner, address indexed gauge, uint tokenId);
    event LZReceive(uint256 activePeriod, uint256 totalClaimable, address[] gauges, uint256[] amounts);

    constructor(
        address __ve, 
        address _factory, 
        address  _gauges, 
        address _bribes,
        address _lzEndpoint
    ) NonblockingLzApp(_lzEndpoint) {
        _ve = __ve;
        factory = _factory;
        base = IVotingEscrow(__ve).token();
        gaugefactory = _gauges;
        bribefactory = _bribes;
        governor = msg.sender;
        emergencyCouncil = msg.sender;
    }      

    function setGovernor(address _governor) public {
        require(msg.sender == governor);
        governor = _governor;
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == emergencyCouncil);
        emergencyCouncil = _council;
    }

    function createGauge(address _pool, address _mainGauge) external returns (address) {
        require(msg.sender == governor, "Only governor");
        require(gauges[_pool] == address(0x0), "exists");
        require(mainChainGauges[_mainGauge] == address(0x0), "mainchain gauge exists");
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

        string memory _type =  string.concat("MF LP Fees: ", IERC20(_pool).symbol() );
        address _internal_bribe = IBribeFactory(bribefactory).createBribe(owner(), tokenA, tokenB, _type);

        // _type = string.concat("MF Bribes: ", IERC20(_pool).symbol() );
        address _external_bribe = address(0); // IBribeFactory(bribefactory).createBribe(owner(), tokenA, tokenB, _type);

        address _gauge = IGaugeFactory(gaugefactory).createGaugeV2(base, _ve, _pool, address(this), _internal_bribe, _external_bribe, address(0), isPair);
        mainChainGauges[_mainGauge] = _gauge;

        IERC20(base).approve(_gauge, type(uint).max);
        internal_bribes[_gauge] = _internal_bribe;
        external_bribes[_gauge] = _external_bribe;
        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;
        // _updateFor(_gauge);
        pools.push(_pool);
        emit GaugeCreated(_gauge, msg.sender, _internal_bribe, _external_bribe, _pool);
        return _gauge;
    }

    function killGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        // claimable[_gauge] = 0;
        emit GaugeKilled(_gauge);
    }

    function reviveGauge(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(!isAlive[_gauge], "gauge already alive");
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    function attachTokenToGauge(uint tokenId, address account) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]); // killed gauges cannot attach tokens to themselves
        if (tokenId > 0) IVotingEscrow(_ve).attach(tokenId);
        emit Attach(account, msg.sender, tokenId);
    }

    function emitDeposit(uint tokenId, address account, uint amount) external {
        require(isGauge[msg.sender]);
        require(isAlive[msg.sender]);
        emit Deposit(account, msg.sender, tokenId, amount);
    }

    function detachTokenFromGauge(uint tokenId, address account) external {
        require(isGauge[msg.sender]);
        if (tokenId > 0) IVotingEscrow(_ve).detach(tokenId);
        emit Detach(account, msg.sender, tokenId);
    }

    function emitWithdraw(uint tokenId, address account, uint amount) external {
        require(isGauge[msg.sender]);
        emit Withdraw(account, msg.sender, tokenId, amount);
    }

    function length() external view returns (uint) {
        return pools.length;
    }

    function claimRewards(address[] memory _gauges, address[][] memory _tokens) external {
        for (uint i = 0; i < _gauges.length; i++) {
            IGauge(_gauges[i]).getReward(msg.sender, _tokens[i]);
        }
    }

    function claimFees(address[] memory _fees, address[][] memory _tokens, uint _tokenId) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
        for (uint i = 0; i < _fees.length; i++) {
            IBribe(_fees[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

    function distributeFees(address[] memory _gauges) external {
        for (uint i = 0; i < _gauges.length; i++) {
            if (IGauge(_gauges[i]).isForPair()){
                IGauge(_gauges[i]).claimFees();
            }
        }
    }

    function flipOneStepProcess() external {
        require(msg.sender == governor, "Only governor");
        lzOneStepProcess = !lzOneStepProcess;
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory, uint64, bytes memory _payload) internal virtual override {
        require(SRC_CHAIN_ID == _srcChainId, "Wrong srcChainId");

        (uint256 activePeriod, uint256 totalClaimable, address[] memory _gauges, uint256[] memory _amounts) = abi.decode(_payload, (uint256, uint256, address[], uint256[]));
        
        // Update active period if needed
        if (activePeriod > active_period) {
            active_period = activePeriod;
        }

        IOFT(base).mintWeeklyRewards(address(this), totalClaimable);

        for (uint256 i = 0; i < _gauges.length; i++) {
            availableEmissions[activePeriod][_gauges[i]] += _amounts[i];
        }

        if (lzOneStepProcess) {
            distribute(activePeriod, _gauges);
        }

        emit LZReceive(activePeriod, totalClaimable, _gauges, _amounts);
    }

    function distribute(uint256 _currentTimestamp, address[] memory _mainGauges) public nonReentrant { 
        address _mainGauge; // mainchain gauge
        address _gauge; // sidechain gauge
        for (uint256 i = 0; i < _mainGauges.length; i++) {
            _mainGauge = _mainGauges[i];
            _gauge = mainChainGauges[_mainGauge]; // get mapped gauge to mainchain gauge
            if (_gauge == address(0)) {
                // In case mainGauge isn't mapped on sidechain, this means that governor needs to createGauge on sidechain for this mainGauge
                return;
            }

            uint256 _claimable = availableEmissions[_currentTimestamp][_mainGauge];

            uint256 lastTimestamp = gaugesDistributionTimestmap[_gauge];
            // distribute only if claimable is > 0 and currentEpoch != lastepoch
            if (_claimable > 0 && lastTimestamp < _currentTimestamp) {
                IGauge(_gauge).notifyRewardAmount(base, _claimable);
                emit DistributeReward(msg.sender, _gauge, _claimable);
                gaugesDistributionTimestmap[_gauge] = _currentTimestamp;
                availableEmissions[_currentTimestamp][_mainGauge] = 0;
            }
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function setBribeFactory(address _bribeFactory) external {
        require(msg.sender == emergencyCouncil);
        bribefactory = _bribeFactory;
    }

    function setGaugeFactory(address _gaugeFactory) external {
        require(msg.sender == emergencyCouncil);
        gaugefactory = _gaugeFactory;
    }

    function setPairFactory(address _factory) external {
        require(msg.sender == emergencyCouncil);
        factory = _factory;
    }

    function killGaugeTotally(address _gauge) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isAlive[_gauge], "gauge already dead");
        isAlive[_gauge] = false;
        address _pool = poolForGauge[_gauge];
        internal_bribes[_gauge] = address(0);
        external_bribes[_gauge] = address(0);
        gauges[_pool] = address(0);
        poolForGauge[_gauge] = address(0);
        isGauge[_gauge] = false;
        isAlive[_gauge] = false;
        // claimable[_gauge] = 0;
        emit GaugeKilled(_gauge);
    }

    function increaseGaugeApprovals(address _gauge) external {
        require(msg.sender == emergencyCouncil);
        require(isGauge[_gauge] = true);
        IERC20(base).approve(_gauge, 0);
        IERC20(base).approve(_gauge, type(uint).max);
    }

    function setNewBribe(address _gauge, address _internal, address _external) external {
        require(msg.sender == emergencyCouncil);
        require(isGauge[_gauge] = true);
        internal_bribes[_gauge] = _internal;
        external_bribes[_gauge] = _external;
    }

    // Moved minter & active_period here, because bribes contract needs it, and we don't have minter on sidechain
    function minter() external view returns (address) {
        return address(this);
    }
    
}

