pragma solidity 0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./BufferBinaryPool.sol";
import "./AccessControl.sol";

/**
 * @author Heisenberg
 * @title Buffer Options Config
 * @notice Maintains all the configurations for the options contracts
 */
contract OptionsConfig is IOptionsConfig, AccessControl {
    BufferBinaryPool public pool;

    address public override circuitBreakerContract;
    address public override settlementFeeDisbursalContract;
    address public override optionStorageContract;
    address public override creationWindowContract;
    address public override poolOIStorageContract;
    address public override poolOIConfigContract;
    address public override marketOIConfigContract;
    address public override boosterContract;
    uint32 public override maxPeriod = 24 hours;
    uint32 public override minPeriod = 3 minutes;
    uint32 public override earlyCloseThreshold = 1 minutes;
    uint32 public override iv;

    uint256 public override minFee = 1e6;
    uint256 public override platformFee = 1e5;
    bool public override isEarlyCloseAllowed;
    uint256 public override spreadConfig1 = 4e3;
    uint256 public override spreadConfig2 = 8e3;
    uint32 public override spreadFactor = 500;
    uint32 public ivFactorITM = 2e2;
    uint32 public ivFactorOTM = 50;
    bytes32 public constant CONTRACT_UPDATOR = keccak256("CONTRACT_UPDATOR");
    bytes32 public constant FEE_UPDATOR = keccak256("FEE_UPDATOR");
    bytes32 public constant IV_UPDATOR = keccak256("IV_UPDATOR");
    bytes32 public constant PERIOD_UPDATOR = keccak256("PERIOD_UPDATOR");

    constructor(BufferBinaryPool _pool) {
        pool = _pool;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier checkRole(bytes32 role) {
        require(
            hasRole(role, msg.sender) ||
                hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Wrong Role"
        );
        _;
    }

    function setBoosterContract(
        address _boosterContract
    ) external checkRole(CONTRACT_UPDATOR) {
        boosterContract = _boosterContract;
        emit UpdateBoosterContract(_boosterContract);
    }

    function setCircuitBreakerContract(
        address _circuitBreakerContract
    ) external checkRole(CONTRACT_UPDATOR) {
        circuitBreakerContract = _circuitBreakerContract;
        emit UpdateCircuitBreakerContract(_circuitBreakerContract);
    }

    function setCreationWindowContract(
        address _creationWindowContract
    ) external checkRole(CONTRACT_UPDATOR) {
        creationWindowContract = _creationWindowContract;
        emit UpdateCreationWindowContract(_creationWindowContract);
    }

    function setMinFee(uint256 _minFee) external checkRole(FEE_UPDATOR) {
        minFee = _minFee;
        emit UpdateMinFee(_minFee);
    }

    function setIV(uint32 _iv) external checkRole(IV_UPDATOR) {
        iv = _iv;
        emit UpdateIV(_iv);
    }

    function setPlatformFee(
        uint256 _platformFee
    ) external checkRole(FEE_UPDATOR) {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    function setSettlementFeeDisbursalContract(
        address _settlementFeeDisbursalContract
    ) external checkRole(CONTRACT_UPDATOR) {
        settlementFeeDisbursalContract = _settlementFeeDisbursalContract;
        emit UpdateSettlementFeeDisbursalContract(
            _settlementFeeDisbursalContract
        );
    }

    function setOptionStorageContract(
        address _optionStorageContract
    ) external checkRole(CONTRACT_UPDATOR) {
        optionStorageContract = _optionStorageContract;
        emit UpdateOptionStorageContract(_optionStorageContract);
    }

    function setMaxPeriod(
        uint32 _maxPeriod
    ) external checkRole(PERIOD_UPDATOR) {
        require(
            _maxPeriod <= 1 days,
            "MaxPeriod should be less than or equal to 1 day"
        );
        require(
            _maxPeriod >= minPeriod,
            "MaxPeriod needs to be greater than or equal the min period"
        );
        maxPeriod = _maxPeriod;
        emit UpdateMaxPeriod(_maxPeriod);
    }

    function setMinPeriod(
        uint32 _minPeriod
    ) external checkRole(PERIOD_UPDATOR) {
        require(
            _minPeriod >= 1 minutes,
            "MinPeriod needs to be greater than 1 minute"
        );
        minPeriod = _minPeriod;
        emit UpdateMinPeriod(_minPeriod);
    }

    function setPoolOIStorageContract(
        address _poolOIStorageContract
    ) external checkRole(CONTRACT_UPDATOR) {
        poolOIStorageContract = _poolOIStorageContract;
        emit UpdatePoolOIStorageContract(_poolOIStorageContract);
    }

    function setPoolOIConfigContract(
        address _poolOIConfigContract
    ) external checkRole(CONTRACT_UPDATOR) {
        poolOIConfigContract = _poolOIConfigContract;
        emit UpdatePoolOIConfigContract(_poolOIConfigContract);
    }

    function setMarketOIConfigContract(
        address _marketOIConfigContract
    ) external checkRole(CONTRACT_UPDATOR) {
        marketOIConfigContract = _marketOIConfigContract;
        emit UpdateMarketOIConfigContract(_marketOIConfigContract);
    }

    function setEarlyCloseThreshold(
        uint32 _earlyCloseThreshold
    ) external checkRole(PERIOD_UPDATOR) {
        earlyCloseThreshold = _earlyCloseThreshold;
        emit UpdateEarlyCloseThreshold(_earlyCloseThreshold);
    }

    function toggleEarlyClose()
        external
        checkRole(keccak256("EARLY_CLOSE_UPDATOR"))
    {
        isEarlyCloseAllowed = !isEarlyCloseAllowed;
        emit UpdateEarlyClose(isEarlyCloseAllowed);
    }

    function setIVFactorITM(
        uint32 _ivFactorITM
    ) external checkRole(IV_UPDATOR) {
        ivFactorITM = _ivFactorITM;
        emit UpdateIVFactorITM(ivFactorITM);
    }

    function setIVFactorOTM(
        uint32 _ivFactorOTM
    ) external checkRole(IV_UPDATOR) {
        ivFactorOTM = _ivFactorOTM;
        emit UpdateIVFactorOTM(ivFactorOTM);
    }

    function getFactoredIv(bool isITM) external view override returns (uint32) {
        return isITM ? (iv * ivFactorITM) / 100 : (iv * ivFactorOTM) / 100;
    }
}

