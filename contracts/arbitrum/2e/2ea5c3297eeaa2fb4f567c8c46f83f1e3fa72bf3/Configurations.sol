// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AccessControlUpgradeable.sol";
import {IConfigurations} from "./IConfigurations.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Configurations keeps track of values that are voted on
///        which govern the rest of the lending protocol
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Configurations is IConfigurations, AccessControlUpgradeable {
    uint256 public maxBorrow;
    uint256 public impliedVolatility;
    uint256 public expirationCycle;
    int256 public riskFreeRate;
    address public pricingOracle;
    address public premiumPricer;
    uint256 public minBorrow;
    uint256 public liquidationThreshold;
    uint256 public premiumFeeProration;
    uint256 public minimumPremiumFee;
    uint256 public protocolFee;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    event ChangedMaxBorrow(
        address indexed _operator,
        uint256 _previousMaxBorrow,
        uint256 _currentMaxBorrow
    );

    event ChangedImpliedVolitility(
        address indexed _operator,
        uint256 _previousImpliedVolitility,
        uint256 _currentImpliedVolitility
    );

    event ChangedExpirationCycle(
        address indexed _operator,
        uint256 _previousExpirationCycle,
        uint256 _currentExpirationCycle
    );

    event ChangedRiskFreeRate(
        address indexed _operator,
        int256 _previousRiskFreeRate,
        int256 _currentRiskFreeRate
    );

    event ChangedPricingOracle(
        address indexed _operator,
        address _previousPricingOracle,
        address _currentPricingOracle
    );

    event ChangedPremiumPricer(
        address indexed _operator,
        address _previousPremiumPricer,
        address _currentPremiumPricer
    );

    event ChangedMinBorrow(
        address indexed _operator,
        uint256 _previousMinBorrow,
        uint256 _currentMinBorrow
    );

    event ChangedLiquidationThreshold(
        address indexed _operator,
        uint256 _previousLiquidationThreshold,
        uint256 _currentLiquidationThreshold
    );

    event ChangedPremiumFeeProration(
        address indexed _operator,
        uint256 _previousPremiumFeeProration,
        uint256 _currentPremiumFeeProration
    );

    event ChangedMinimumPremiumFee(
        address indexed _operator,
        uint256 _previousMinimumPremiumFee,
        uint256 _currentMinimumPremiumFee
    );

    event ChangedProtocolFee(
        address indexed _operator,
        uint256 _previousProtocolFee,
        uint256 _currentProtocolFee
    );

    function initialize(
        uint256 _maxBorrow,
        uint256 _impliedVolatility,
        uint256 _expirationCycle,
        int256 _riskFreeRate,
        address _pricingOracle,
        address _premiumPricer,
        uint256 _minBorrow,
        uint256 _liquidationThreshold,
        uint256 _premiumFeeProration,
        uint256 _minimumPremiumFee,
        uint256 _protocolFee
    ) external initializer {
        __AccessControl_init();

        maxBorrow = _maxBorrow;
        impliedVolatility = _impliedVolatility;
        expirationCycle = _expirationCycle;
        riskFreeRate = _riskFreeRate;
        pricingOracle = _pricingOracle;
        premiumPricer = _premiumPricer;
        minBorrow = _minBorrow;
        liquidationThreshold = _liquidationThreshold;
        premiumFeeProration = _premiumFeeProration;
        minimumPremiumFee = _minimumPremiumFee;
        protocolFee = _protocolFee;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setMaxBorrow(uint256 _maxBorrow) public onlyAdmin {
        emit ChangedMaxBorrow(msg.sender, maxBorrow, _maxBorrow);
        maxBorrow = _maxBorrow;
    }

    function setImpliedVolitility(uint256 _impliedVolatility) public onlyAdmin {
        emit ChangedImpliedVolitility(
            msg.sender,
            impliedVolatility,
            _impliedVolatility
        );
        impliedVolatility = _impliedVolatility;
    }

    function setExpirationCycle(uint256 _expirationCycle) public onlyAdmin {
        emit ChangedExpirationCycle(
            msg.sender,
            expirationCycle,
            _expirationCycle
        );
        expirationCycle = _expirationCycle;
    }

    function setRiskFreeRate(int256 _riskFreeRate) public onlyAdmin {
        emit ChangedRiskFreeRate(msg.sender, riskFreeRate, _riskFreeRate);
        riskFreeRate = _riskFreeRate;
    }

    function setPricingOracle(address _pricingOracle) public onlyAdmin {
        emit ChangedPricingOracle(msg.sender, pricingOracle, _pricingOracle);
        pricingOracle = _pricingOracle;
    }

    function setPremiumPricer(address _premiumPricer) public onlyAdmin {
        emit ChangedPremiumPricer(msg.sender, premiumPricer, _premiumPricer);
        premiumPricer = _premiumPricer;
    }

    function setMinBorrow(uint256 _minBorrow) public onlyAdmin {
        emit ChangedMinBorrow(msg.sender, minBorrow, _minBorrow);
        minBorrow = _minBorrow;
    }

    function setLiquidationThreshold(
        uint256 _liquidationThreshold
    ) public onlyAdmin {
        emit ChangedLiquidationThreshold(
            msg.sender,
            liquidationThreshold,
            _liquidationThreshold
        );
        liquidationThreshold = _liquidationThreshold;
    }

    function setPremiumFeeProration(
        uint256 _premiumFeeProration
    ) public onlyAdmin {
        emit ChangedPremiumFeeProration(
            msg.sender,
            premiumFeeProration,
            _premiumFeeProration
        );
        premiumFeeProration = _premiumFeeProration;
    }

    function setMinimumPremiumFee(uint256 _minimumPremiumFee) public onlyAdmin {
        emit ChangedMinimumPremiumFee(
            msg.sender,
            minimumPremiumFee,
            _minimumPremiumFee
        );
        minimumPremiumFee = _minimumPremiumFee;
    }

    function setProtocolFee(uint256 _protocolFee) public onlyAdmin {
        emit ChangedProtocolFee(msg.sender, protocolFee, _protocolFee);
        protocolFee = _protocolFee;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Configurations: caller not admin"
        );
        _;
    }
}

