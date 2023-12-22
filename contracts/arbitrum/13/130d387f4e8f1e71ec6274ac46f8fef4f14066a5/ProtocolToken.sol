// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./ERC20.sol";
import "./AccessControl.sol";
import "./Math.sol";

import "./IProtocolToken.sol";

contract BigPeenShit is ERC20, AccessControl, IProtocolToken {
    bytes32 public TREASURY_ROLE = keccak256("TREASURY");
    bytes32 public OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    uint256 public constant MAX_EMISSION_RATE = 0.01 ether;
    uint256 public constant MAX_SUPPLY_LIMIT = 200000 ether; // TODO: These emission settings
    uint256 public constant ALLOCATION_PRECISION = 100;

    uint256 public elasticMaxSupply; // Once deployed, controlled through governance only
    uint256 public emissionRate; // Token emission per second

    uint256 public override lastEmissionTime;
    uint256 public masterReserve; // Pending rewards for the master

    // Allocations emitted over time. When < 100%, the rest is minted into the treasury (default 15%)
    uint256 public farmingAllocation = 50; // = 50%

    address public masterAddress;
    address public treasuryAddress;

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event ClaimMasterRewards(uint256 amount);
    event AllocationsDistributed(uint256 masterShare, uint256 treasuryShare);
    event InitializeMasterAddress(address masterAddress);
    event InitializeEmissionStart(uint256 startTime);
    event UpdateAllocations(uint256 farmingAllocation, uint256 treasuryAllocation);
    event UpdateEmissionRate(uint256 previousEmissionRate, uint256 newEmissionRate);
    event UpdateMaxSupply(uint256 previousMaxSupply, uint256 newMaxSupply);
    event UpdateTreasuryAddress(address previousTreasuryAddress, address newTreasuryAddress);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/

    /*
     * @dev Throws error if called by any account other than the master
     */
    modifier onlyMaster() {
        require(msg.sender == masterAddress, "GrailToken: caller is not the master");
        _;
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, _msgSender()), "Only admin");
        _;
    }

    modifier onlyTreasury() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Only treasury");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _initialSupply,
        uint256 _initialEmissionRate,
        address _treasuryAddress
    ) ERC20(_name, _symbol) {
        require(_initialEmissionRate <= MAX_EMISSION_RATE, "invalid emission rate");
        require(_maxSupply <= MAX_SUPPLY_LIMIT, "invalid initial maxSupply");
        require(_initialSupply < _maxSupply, "invalid initial supply");
        require(_treasuryAddress != address(0), "invalid treasury address");

        elasticMaxSupply = _maxSupply;
        emissionRate = _initialEmissionRate;
        treasuryAddress = _treasuryAddress;

        _mint(msg.sender, _initialSupply);

        _grantRole(DEFAULT_ADMIN_ROLE, _treasuryAddress);
        _grantRole(OPERATOR_ROLE, _treasuryAddress);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Returns total master allocation
     */
    function masterAllocation() public view returns (uint256) {
        return farmingAllocation;
    }

    /**
     * @dev Returns master emission rate
     */
    function masterEmissionRate() public view override returns (uint256) {
        return (emissionRate * farmingAllocation) / ALLOCATION_PRECISION;
    }

    /**
     * @dev Returns treasury allocation
     */
    function treasuryAllocation() public view returns (uint256) {
        return uint256(ALLOCATION_PRECISION) - masterAllocation();
    }

    /*****************************************************************/
    /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
    /*****************************************************************/

    /**
     * @dev Mint rewards and distribute it between master and treasury
     *
     * Treasury share is directly minted to the treasury address
     * Master incentives are minted into this contract and claimed later by the master contract
     */
    function emitAllocations() public {
        uint256 circulatingSupply = totalSupply();
        uint256 currentBlockTimestamp = block.timestamp;

        uint256 _lastEmissionTime = lastEmissionTime; // gas saving
        uint256 _maxSupply = elasticMaxSupply; // gas saving

        // if already up to date or not started
        if (currentBlockTimestamp <= _lastEmissionTime || _lastEmissionTime == 0) {
            return;
        }

        // if max supply is already reached or emissions deactivated
        if (_maxSupply <= circulatingSupply || emissionRate == 0) {
            lastEmissionTime = currentBlockTimestamp;
            return;
        }

        uint256 newEmissions = (currentBlockTimestamp - _lastEmissionTime) * emissionRate;

        // cap new emissions if exceeding max supply
        if (_maxSupply < circulatingSupply + newEmissions) {
            newEmissions = _maxSupply - circulatingSupply;
        }

        // calculate master and treasury shares from new emissions
        uint256 masterShare = (newEmissions * masterAllocation()) / ALLOCATION_PRECISION;
        // sub to avoid rounding errors
        uint256 treasuryShare = newEmissions - masterShare;

        lastEmissionTime = currentBlockTimestamp;

        // add master shares to its claimable reserve
        masterReserve = masterReserve + masterShare;
        // mint shares
        _mint(address(this), masterShare);
        _mint(treasuryAddress, treasuryShare);

        emit AllocationsDistributed(masterShare, treasuryShare);
    }

    /**
     * @dev Sends to Master contract the asked "amount" from masterReserve
     *
     * Can only be called by the MasterContract
     */
    function claimMasterRewards(uint256 amount) external override onlyMaster returns (uint256 effectiveAmount) {
        // update emissions
        emitAllocations();

        // cap asked amount with available reserve
        effectiveAmount = Math.min(masterReserve, amount);

        // if no rewards to transfer
        if (effectiveAmount == 0) {
            return effectiveAmount;
        }

        // remove claimed rewards from reserve and transfer to master
        masterReserve = masterReserve - effectiveAmount;
        _transfer(address(this), masterAddress, effectiveAmount);

        emit ClaimMasterRewards(effectiveAmount);
    }

    /**
     * @dev Burns "amount" by sending it to BURN_ADDRESS
     */
    function burn(uint256 amount) external override {
        _transfer(msg.sender, BURN_ADDRESS, amount);
    }

    /*****************************************************************/
    /****************** EXTERNAL ADMIN FUNCTIONS  ******************/
    /*****************************************************************/

    /**
     * @dev Setup Master contract address
     *
     * Can only be initialized once
     * Must only be called by the owner
     */
    function initializeMasterAddress(address _masterAddress) external onlyOperator {
        require(masterAddress == address(0), "initializeMasterAddress: master already initialized");
        require(_masterAddress != address(0), "initializeMasterAddress: master initialized to zero address");

        masterAddress = _masterAddress;
        emit InitializeMasterAddress(_masterAddress);
    }

    /**
     * @dev Set emission start time
     *
     * Can only be initialized once
     * Must only be called by the owner
     */
    function initializeEmissionStart(uint256 startTime) external onlyOperator {
        require(lastEmissionTime == 0, "initializeEmissionStart: emission start already initialized");
        require(block.timestamp < startTime, "initializeEmissionStart: invalid");

        lastEmissionTime = startTime;
        emit InitializeEmissionStart(startTime);
    }

    /**
     * @dev Updates emission allocations between farming incentives, legacy holders and treasury (remaining share)
     *
     * Must only be called by the owner
     */
    function updateAllocations(uint256 _farmingAllocation) external onlyTreasury {
        // apply emissions before changes
        emitAllocations();

        // total sum of allocations can't be > 100%
        require(_farmingAllocation <= 100, "updateAllocations: total allocation is too high");

        // set new allocations
        farmingAllocation = _farmingAllocation;

        emit UpdateAllocations(_farmingAllocation, treasuryAllocation());
    }

    /**
     * @dev Updates GRAIL emission rate per second
     *
     * Must only be called by the owner
     */
    function updateEmissionRate(uint256 _emissionRate) external onlyTreasury {
        require(_emissionRate <= MAX_EMISSION_RATE, "updateEmissionRate: can't exceed maximum");

        // apply emissions before changes
        emitAllocations();

        emit UpdateEmissionRate(emissionRate, _emissionRate);
        emissionRate = _emissionRate;
    }

    /**
     * @dev Updates GRAIL max supply
     *
     * Must only be called by the owner
     */
    function updateMaxSupply(uint256 _maxSupply) external onlyTreasury {
        require(_maxSupply >= totalSupply(), "updateMaxSupply: can't be lower than current circulating supply");
        require(_maxSupply <= MAX_SUPPLY_LIMIT, "updateMaxSupply: invalid maxSupply");

        emit UpdateMaxSupply(elasticMaxSupply, _maxSupply);
        elasticMaxSupply = _maxSupply;
    }

    /**
     * @dev Updates treasury address
     *
     * Must only be called by owner
     */
    function updateTreasuryAddress(address _treasuryAddress) external onlyOperator {
        require(_treasuryAddress != address(0), "updateTreasuryAddress: invalid address");

        emit UpdateTreasuryAddress(treasuryAddress, _treasuryAddress);
        treasuryAddress = _treasuryAddress;
    }
}

