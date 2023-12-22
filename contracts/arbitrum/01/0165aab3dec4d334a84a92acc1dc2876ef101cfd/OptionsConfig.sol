pragma solidity 0.8.4;

// SPDX-License-Identifier: BUSL-1.1

import "./BufferBinaryPool.sol";
import "./Ownable.sol";

/**
 * @author Heisenberg
 * @title Buffer Options Config
 * @notice Maintains all the configurations for the options contracts
 */
contract OptionsConfig is Ownable, IOptionsConfig {
    BufferBinaryPool public pool;

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

    constructor(BufferBinaryPool _pool) {
        pool = _pool;
    }

    function setBoosterContract(address _boosterContract) external onlyOwner {
        boosterContract = _boosterContract;
        emit UpdateBoosterContract(_boosterContract);
    }

    function setCreationWindowContract(
        address _creationWindowContract
    ) external onlyOwner {
        creationWindowContract = _creationWindowContract;
        emit UpdateCreationWindowContract(_creationWindowContract);
    }

    function setMinFee(uint256 _minFee) external onlyOwner {
        minFee = _minFee;
        emit UpdateMinFee(_minFee);
    }

    function setIV(uint32 _iv) external onlyOwner {
        iv = _iv;
        emit UpdateIV(_iv);
    }

    function setPlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    function setSettlementFeeDisbursalContract(
        address _settlementFeeDisbursalContract
    ) external onlyOwner {
        settlementFeeDisbursalContract = _settlementFeeDisbursalContract;
        emit UpdateSettlementFeeDisbursalContract(
            _settlementFeeDisbursalContract
        );
    }

    function setOptionStorageContract(
        address _optionStorageContract
    ) external onlyOwner {
        optionStorageContract = _optionStorageContract;
        emit UpdateOptionStorageContract(_optionStorageContract);
    }

    function setMaxPeriod(uint32 _maxPeriod) external onlyOwner {
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

    function setMinPeriod(uint32 _minPeriod) external onlyOwner {
        require(
            _minPeriod >= 1 minutes,
            "MinPeriod needs to be greater than 1 minute"
        );
        minPeriod = _minPeriod;
        emit UpdateMinPeriod(_minPeriod);
    }

    function setPoolOIStorageContract(
        address _poolOIStorageContract
    ) external onlyOwner {
        poolOIStorageContract = _poolOIStorageContract;
        emit UpdatePoolOIStorageContract(_poolOIStorageContract);
    }

    function setPoolOIConfigContract(
        address _poolOIConfigContract
    ) external onlyOwner {
        poolOIConfigContract = _poolOIConfigContract;
        emit UpdatePoolOIConfigContract(_poolOIConfigContract);
    }

    function setMarketOIConfigContract(
        address _marketOIConfigContract
    ) external onlyOwner {
        marketOIConfigContract = _marketOIConfigContract;
        emit UpdateMarketOIConfigContract(_marketOIConfigContract);
    }

    function setEarlyCloseThreshold(
        uint32 _earlyCloseThreshold
    ) external onlyOwner {
        earlyCloseThreshold = _earlyCloseThreshold;
        emit UpdateEarlyCloseThreshold(_earlyCloseThreshold);
    }

    function toggleEarlyClose() external onlyOwner {
        isEarlyCloseAllowed = !isEarlyCloseAllowed;
        emit UpdateEarlyClose(isEarlyCloseAllowed);
    }

    function setSpreadConfig1(uint256 _spreadConfig1) external onlyOwner {
        spreadConfig1 = _spreadConfig1;
        emit UpdateSpreadConfig1(spreadConfig1);
    }

    function setSpreadConfig2(uint256 _spreadConfig2) external onlyOwner {
        spreadConfig2 = _spreadConfig2;
        emit UpdateSpreadConfig2(spreadConfig2);
    }

    function setSpreadFactor(uint32 _spreadFactor) external onlyOwner {
        spreadFactor = _spreadFactor;
        emit UpdateSpreadFactor(spreadFactor);
    }

    function setIVFactorITM(uint32 _ivFactorITM) external onlyOwner {
        ivFactorITM = _ivFactorITM;
        emit UpdateIVFactorITM(ivFactorITM);
    }

    function setIVFactorOTM(uint32 _ivFactorOTM) external onlyOwner {
        ivFactorOTM = _ivFactorOTM;
        emit UpdateIVFactorOTM(ivFactorOTM);
    }

    function getFactoredIv(bool isITM) external view override returns (uint32) {
        return isITM ? (iv * ivFactorITM) / 100 : (iv * ivFactorOTM) / 100;
    }
}

