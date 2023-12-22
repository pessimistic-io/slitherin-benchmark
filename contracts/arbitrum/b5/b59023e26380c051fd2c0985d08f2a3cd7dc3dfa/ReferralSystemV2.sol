// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./BaseConstants.sol";
import "./IMintable.sol";
import "./IBurnable.sol";
import "./IPriceManager.sol";
import "./IReferralSystemV2.sol";
import "./ISettingsManagerV2.sol";
import "./IVaultV2Simplify.sol";

contract ReferralSystemV2 is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IReferralSystemV2, BaseConstants {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    //Standard tier
    struct StandardTier {
        uint256 rebatePercentage;
        uint256 discountSharePercentage;
        bool isActivate;
    }

    //Premium tier
    struct PremiumTier {
        uint256 rebatePercentage;
        uint256 esRebatePercentage;
        uint256 discountSharePercentage;
        bool isActivate;
    }

    struct ReferralCodeStat {
        uint256 totalRebate;
        uint256 totalDiscountshare;
        uint256 totalEsRebate;
        uint256 totalEsROSXRebate;
    }

    struct ConvertHistory {
        uint256 amount;
        uint256 timestamp;
    }

    EnumerableSetUpgradeable.UintSet private tiersType;
    ISettingsManagerV2 public settingsManager;
    IPriceManager public priceManager;
    IVaultV2Simplify public vault;
    address public rUSD;
    address public ROSX;
    address public esROSX;

    mapping(address => mapping(uint256 => uint256)) public refTiers;
    mapping(uint256 => StandardTier) public standardTiers;
    mapping(uint256 => PremiumTier) public premiumTiers;

    mapping(bytes32 => address) public codeOwners;
    mapping(address => bytes32) public traderReferralCode;
    mapping(bytes32 => ReferralCodeStat) public codeStats;

    mapping(address => bool) public isHandler;
    mapping(bytes32 => bool) public blacklistCodes;
    mapping(address => bool) public blacklistOwners;

    uint256 public maxCodePerOwner;
    bool public isAllowOverrideCode;
    uint256 public nonStableMaxPriceUpdatedDelay;
    mapping(address => TIER_TYPE) public tierOwners;
    mapping(address => EnumerableSetUpgradeable.Bytes32Set) private codeUsage;
    mapping(bytes32 => EnumerableSetUpgradeable.AddressSet) private codeLink;
    uint256[50] private __gap;

    event FinalInitialize(
        address rUSD,
        address ROSX,
        address esROSX, 
        address settingsManager, 
        address priceManager, 
        address vault
    );
    event SetHandler(address handler, bool isActive);
    event SetTraderReferralCode(address account, bytes32 code);
    event SetStandardTier(uint256 tierId, uint256 rebatePercentage, uint256 discountSharePercentage);
    event SetPremiumTier(uint256 tierId, uint256 rebatePercentages, uint256 esRebatePercentages, uint256 discountSharePercentage);
    event SetReferrerTier(address referrer, TIER_TYPE tierType, uint256 tierId);
    event RemoveReferrerTier(address referrer);
    event RegisterCode(address account, bytes32 code);
    event ChangeCodeOwner(address account, address newAccount, bytes32 code);

    event DeactivateTier(TIER_TYPE tierType, uint256 tierId);
    event SetCodeBlacklist(bytes32[] codes, bool[] isBlacklist);
    event SetOwnerBlacklist(address[] owners, bool[] isBlacklist);
    event SetMaxCodePerOwner(uint256 maxCodePerOwner);
    event SetAllowOverrideCode(bool isAllowOverrideCode);
    event SetNonStableMaxPriceUpdatedDelay(uint256 _nonStableMaxPriceUpdatedDelay);
    event IncreaseCodeStat(bytes32 code, uint256 discountShareAmount, uint256 rebateAmount, uint256 esROSXRebateAmount);
    event FixCodeStat(bytes32 code, uint256 newTotalDiscountshare, uint256 newTotalRebate, uint256 newTotalEsROSXRebate);
    event ConvertRUSD(address recipient, address tokenOut, uint256 rUSD, uint256 amountOut, uint256 timestamp);
    event ReferralDelievered(address _account, bytes32 code, address referrer, uint256 amount);
    event EscrowRebateDelivered(
        address referrer,
        uint256 esRebateAmount,
        uint256 price,
        uint256 esROSXAmount,
        bool isSuccess, 
        string err)
    ;

    enum TIER_TYPE {
        NONE,
        STANDARD,
        PREMIUM
    }

    modifier onlyHandler() {
        require(isHandler[msg.sender], "Forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(isHandler[msg.sender] || msg.sender == owner(), "Forbidden");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        address _rUSD,
        address _ROSX,
        address _esROSX, 
        address _settingsManager, 
        address _priceManager, 
        address _vault
    ) public initializer {
        __Ownable_init();
        _initTiersType();

        //Should check all tiers type must have been initialized
        require(tiersType.length() > 0 
            && tiersType.length() == uint256(type(TIER_TYPE).max) + 1, "Invalid tiers type");
        initializeTiers();
        finalInitialize(_rUSD, _ROSX, _esROSX, _settingsManager, _priceManager, _vault);
    }

    function finalInitialize(address _rUSD, address _ROSX, address _esROSX, address _settingsManager, address _priceManager, address _vault) internal {
        _validateInternalContracts(_rUSD, _settingsManager, _priceManager, _vault);
        rUSD = _rUSD;
        ROSX = _ROSX;
        esROSX = _esROSX;
        settingsManager = ISettingsManagerV2(_settingsManager);
        priceManager = IPriceManager(_priceManager);
        vault = IVaultV2Simplify(_vault);
        emit FinalInitialize(_rUSD, ROSX, esROSX, _settingsManager, _priceManager, _vault);
    }

    /*
    @dev: Declarer all tiers type for initialization or upgrade. 
    * If upgrade, the position of 2 value must not change:
    *   [0] must be TIER_TYPE.NONE
    *   [1] must be TIER_TYPE.STANDARD
    *   [2] must be TIER_TYPE.PREMIUM
    */
    function _initTiersType() internal {
        TIER_TYPE[] memory initTiers = new TIER_TYPE[](3);
        initTiers[0] = TIER_TYPE.NONE;
        initTiers[1] = TIER_TYPE.STANDARD;
        initTiers[2] = TIER_TYPE.PREMIUM;

        for (uint256 i = 0; i < initTiers.length; i++) {
            tiersType.add(uint256(initTiers[i]));
        }
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function setStandardTier(uint256 _tierId, uint256 _rebatePercentage, uint256 _discountSharePercentage) external onlyOwner {
        _valdiateTierAttr(TIER_TYPE.STANDARD, _tierId, _rebatePercentage, _discountSharePercentage);
        StandardTier memory tier = standardTiers[_tierId];
        tier.rebatePercentage = _rebatePercentage;
        tier.discountSharePercentage = _discountSharePercentage;
        tier.isActivate = true;
        standardTiers[_tierId] = tier;
        emit SetStandardTier(_tierId, _rebatePercentage, _discountSharePercentage);
    }

    function setPremiumTier(
        uint256 _tierId, 
        uint256 _rebatePercentage, 
        uint256 _esRebatePercentage, 
        uint256 _discountSharePercentage
    ) external onlyOwner {
        _valdiateTierAttr(TIER_TYPE.PREMIUM, _tierId, _rebatePercentage + _esRebatePercentage, _discountSharePercentage);
        PremiumTier memory tier = premiumTiers[_tierId];
        tier.rebatePercentage = _rebatePercentage;
        tier.esRebatePercentage = _esRebatePercentage;
        tier.discountSharePercentage = _discountSharePercentage;
        tier.isActivate = true;
        premiumTiers[_tierId] = tier;
        emit SetPremiumTier(_tierId, _rebatePercentage, _esRebatePercentage, _discountSharePercentage);
    }

    function deactivateTier(TIER_TYPE _tierType, uint256 _tierId) external onlyAdmin {
        _validateTier(_tierType, _tierId);
        
        if (_tierType == TIER_TYPE.PREMIUM) {
            premiumTiers[_tierId].isActivate = false;
        } else if (_tierType == TIER_TYPE.STANDARD) {
            standardTiers[_tierId].isActivate = false;
        } else {
            //Reserve
            revert("Invalid tierType");
        }

        emit DeactivateTier(_tierType, _tierId);
    }

    function setCodeBlacklist(bytes32[] memory _codes, bool[] memory _isBlacklist) external onlyAdmin {
        require(_codes.length + _isBlacklist.length > 0, "Zero length");
        require(_codes.length == _isBlacklist.length || (_codes.length > 0 && _isBlacklist.length == 1), "Invalid length");

        for (uint256 i = 0; i < _codes.length; i++) {
            blacklistCodes[_codes[i]] = _isBlacklist.length == 1 ? _isBlacklist[0] : _isBlacklist[i];
        }

        emit SetCodeBlacklist(_codes, _isBlacklist);
    }

    function setOwnerBlacklist(address[] memory _owners, bool[] memory _isBlacklist) external onlyAdmin {
        require(_owners.length + _isBlacklist.length > 0, "Zero length");
        require(_owners.length == _isBlacklist.length || (_owners.length > 0 && _isBlacklist.length == 1), "Invalid length");

        for (uint256 i = 0; i < _owners.length; i++) {
            blacklistOwners[_owners[i]] = _isBlacklist.length == 1 ? _isBlacklist[0] : _isBlacklist[i];
        }

        emit SetOwnerBlacklist(_owners, _isBlacklist);
    }

    function setMaxCodePerOwner(uint256 _maxCodePerOwner) external onlyOwner {
        require(_maxCodePerOwner > 0, "Invalid maxCodePerOwner");
        maxCodePerOwner = _maxCodePerOwner;
        emit SetMaxCodePerOwner(_maxCodePerOwner);
    }

    function setAllowOverrideCode(bool _isAllowOverrideCode) external onlyOwner {
        isAllowOverrideCode = _isAllowOverrideCode;
        emit SetAllowOverrideCode(_isAllowOverrideCode);
    }

    function setNonStableMaxPriceUpdatedDelay(uint256 _nonStableMaxPriceUpdatedDelay) external onlyOwner {
        require(_nonStableMaxPriceUpdatedDelay <= settingsManager.maxPriceUpdatedDelay(), "Should smaller than settingsManager value");
        nonStableMaxPriceUpdatedDelay = _nonStableMaxPriceUpdatedDelay;
        emit SetNonStableMaxPriceUpdatedDelay(_nonStableMaxPriceUpdatedDelay);
    }

    function _valdiateTierAttr(
        TIER_TYPE _tierType, 
        uint256 _tierId, 
        uint256 _rebatePercentage, 
        uint256 _discountSharePercentage
    ) internal pure {
        _validateTier(_tierType, _tierId);
        require(_rebatePercentage < BASIS_POINTS_DIVISOR, "Invalid rebatePercentage");
        require(_discountSharePercentage < BASIS_POINTS_DIVISOR, "Invalid discountSharePercentage");
    }

    function _validateTier(TIER_TYPE _tierType, uint256 _tierId) internal pure {
        require(_tierId > 0, "Invalid tierId");
        require(uint256(_tierType) > uint256(TIER_TYPE.NONE) && uint256(_tierType) < uint256(type(TIER_TYPE).max) + 1, "Invalid tierType");
    }

    /*
    @dev: Set referrer tier, revert if exist any other tiers.
    */
    function setReferrerTier(address _referrer, TIER_TYPE _tierType, uint256 _tierId) external onlyAdmin {
        _validateTier(_tierType, _tierId);

        for (uint256 tier = 0 ; tier < uint256(type(TIER_TYPE).max); tier++) {
            if (uint256(_tierType) != tier) {
                require(refTiers[_referrer][tier] == 0, "Existed, remove first");
            }
        }

        _setReferrerTier(_referrer, _tierType, _tierId);
    }

    /*
    @dev: Force set referrer tier, remove all other tiers if existed.
    */
    function forceSetReferrerTier(address _referrer, TIER_TYPE _tierType, uint256 _tierId) external onlyAdmin {
        _validateTier(_tierType, _tierId);
        _removeReferrerTier(_referrer);
        _setReferrerTier(_referrer, _tierType, _tierId);
    }

    function _setReferrerTier(address _referrer, TIER_TYPE _tierType, uint256 _tierId) internal {
        refTiers[_referrer][uint256(_tierType)] = _tierId;
        tierOwners[_referrer] = _tierType;
        emit SetReferrerTier(_referrer, _tierType, _tierId);
    }

    function removeReferrerTier(address _referrer) external onlyAdmin {
        _removeReferrerTier(_referrer);
    }

    function _removeReferrerTier(address _referrer) internal {
        for (uint256 tier = 0 ; tier < uint256(type(TIER_TYPE).max) + 1; tier++) {
            delete refTiers[_referrer][tier];
        }

        emit RemoveReferrerTier(_referrer);
    }

    function setTraderReferralCodeByHandler(address _account, bytes32 refCode) external onlyHandler {
        _setTraderReferralCode(_account, refCode, true);
    }

    function setTraderReferralCode(bytes32 refCode) external {
        _setTraderReferralCode(msg.sender, refCode, isAllowOverrideCode);
    }

    function registerCode(bytes32 refCode) external nonReentrant {
        require(refCode != bytes32(0), "Invalid refCode");
        require(codeOwners[refCode] == address(0), "Code registered");
        
        if (maxCodePerOwner > 0) {
            require(codeUsage[msg.sender].length() < maxCodePerOwner, "Max code number reached");
        }

        //Set the default Standard tier 1 for account does not have tier
        if (tierOwners[msg.sender] == TIER_TYPE.NONE) {
            _setReferrerTier(msg.sender, TIER_TYPE.STANDARD, 1);
        }

        codeOwners[refCode] = msg.sender;
        codeUsage[msg.sender].add(refCode);
        emit RegisterCode(msg.sender, refCode);
    }

    function changeCodeOwnerByHandler(bytes32 _refCode, address _newOwner) external onlyHandler {
        _changeCodeOwner(_refCode, codeOwners[_refCode], _newOwner);
    }

    function changeCodeOwner(bytes32 _refCode, address _newOwner) external nonReentrant {
        require(msg.sender == codeOwners[_refCode], "Forbidden");
        _changeCodeOwner(_refCode, msg.sender, _newOwner);
    }

    function _changeCodeOwner(bytes32 _refCode, address _prevOwner, address _newOwner) internal {
        require(_refCode != bytes32(0), "Invalid refCode");
        require(_prevOwner != _newOwner, "Prev and current owner are same");

        if (maxCodePerOwner > 0) {
            require(codeUsage[_newOwner].length() < maxCodePerOwner - 1, "Max code number reached");
        }

        codeOwners[_refCode] = _newOwner;
        codeUsage[_prevOwner].remove(_refCode);
        codeUsage[_newOwner].add(_refCode);
        emit ChangeCodeOwner(msg.sender, _newOwner, _refCode);
    }

    function getTraderReferralInfo(address _account) external view returns (bytes32, address) {
        bytes32 code = traderReferralCode[_account];
        address referrer;

        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }

        return (code, referrer);
    }

    function _setTraderReferralCode(address _account, bytes32 _refCode, bool _isAllowOverrideCode) private {
        bytes32 prevCode = traderReferralCode[_account];
        require(prevCode != _refCode, "Prev and current refCode are same");

        if (!_isAllowOverrideCode && prevCode != bytes32(0)) {
            revert("Can not change refCode");
        }

        address codeOwner = codeOwners[_refCode];
        require(codeOwner != address(0) && !blacklistOwners[codeOwner] 
            && !blacklistCodes[_refCode], "RefCode not existed or deactivated");
        traderReferralCode[_account] = _refCode;
        codeLink[_refCode].add(_account);
        emit SetTraderReferralCode(_account, _refCode);
    }

    function getDiscountable(address _account) external view override returns(address, uint256, uint256, uint256) {
        address codeOwner;
        uint256 discountPercentage;
        uint256 rebatePercentage;
        uint256 esRebatePercentage;
        (
             , //Not need refCode
            codeOwner, 
            , //Not need tierType 
            , //Not need tierId
            discountPercentage, 
            rebatePercentage, 
            esRebatePercentage
        ) = _getDiscountable(_account);
        return (codeOwner, discountPercentage, rebatePercentage, esRebatePercentage);
    }

    function getDiscountableInternal(address _account, uint256 _fee) external returns(address, uint256, uint256, uint256) {
        return _getDiscountableInternal(_account, _fee);
    }

    function _getDiscountable(address _account) internal view returns(
        bytes32, //refCode
        address, //referrer
        TIER_TYPE, //tierType
        uint256, //tierId
        uint256, //discountPercentage
        uint256, //rebatePercentage
        uint256 //esRebatePercentage
    ) {
        bytes32 refCode = traderReferralCode[_account];

        if (traderReferralCode[_account] == bytes32(0) || blacklistCodes[refCode]) {
            return (bytes32(0), address(0), TIER_TYPE.NONE, 0, 0, 0, 0);
        }

        address referrer = codeOwners[refCode];

        if (referrer == address(0) || blacklistOwners[referrer]) {
            return (bytes32(0), address(0), TIER_TYPE.NONE, 0, 0, 0, 0);
        }

        TIER_TYPE tierType;
        uint256 tierId;
        
        {
            (tierType, tierId) = _getTier(referrer);
        }

        if (tierId == 0 
                || tierType == TIER_TYPE.NONE
                || (tierType == TIER_TYPE.PREMIUM && !premiumTiers[tierId].isActivate) 
                || (tierType == TIER_TYPE.STANDARD && !standardTiers[tierId].isActivate)) {
            return (bytes32(0), address(0), TIER_TYPE.NONE, 0, 0, 0, 0);
        }

        uint256 discountPercentage;

        {
            discountPercentage = _getDiscountPercentage(tierType, tierId);
        }

        return tierType == TIER_TYPE.PREMIUM 
            ?   (
                refCode,
                referrer,
                tierType,
                tierId,
                discountPercentage,
                premiumTiers[tierId].rebatePercentage,
                premiumTiers[tierId].esRebatePercentage
            )
            :  (
                refCode,
                referrer,
                tierType,
                tierId,
                discountPercentage,
                standardTiers[tierId].rebatePercentage,
                0
            );

        // if (tierType == TIER_TYPE.PREMIUM) {
        //     return (
        //         refCode,
        //         referrer,
        //         tierType,
        //         tierId,
        //         discountPercentage,
        //         premiumTiers[tierId].rebatePercentage,
        //         premiumTiers[tierId].esRebatePercentage
        //     );
        // } else if (tierType == TIER_TYPE.STANDARD) {
        //     return (
        //         refCode,
        //         referrer,
        //         tierType,
        //         tierId,
        //         discountPercentage,
        //         standardTiers[tierId].rebatePercentage,
        //         0
        //     );
        // } else if (tierType == TIER_TYPE.NONE) {
        //     //Default tierType = standard and tierId = 1
        //     uint256 defaultTierId = 1;
        //     return (
        //         refCode,
        //         referrer,
        //         TIER_TYPE.STANDARD,
        //         defaultTierId,
        //         discountPercentage,
        //         standardTiers[defaultTierId].rebatePercentage,
        //         0
        //     );
        // } else {
        //     //Reserve
        //     return (
        //         bytes32(0),
        //         address(0),
        //         TIER_TYPE.NONE,
        //         0,
        //         0,
        //         0,
        //         0
        //     );
        // }
    }

    function _getDiscountableInternal(
        address _account,
        uint256 _fee
    ) internal returns(address, uint256, uint256, uint256) {
        require(msg.sender == address(vault), "Forbidden");
        bytes32 refCode;
        address referrer;
        TIER_TYPE tierType;
        uint256 tierId;
        uint256 discountPercentage;
        uint256 rebatePercentage;
        uint256 esRebatePercentage;

        {
            (
                refCode,
                referrer,
                tierType,
                tierId,
                discountPercentage,
                rebatePercentage,
                esRebatePercentage
            ) = _getDiscountable(_account);
        }

        if (refCode == bytes32(0)) {
            return (referrer, discountPercentage, rebatePercentage, esRebatePercentage); 
        }

        _collectRebateAndIncreaseCodeStat(
            _account,
            refCode,
            referrer,
            _fee,
            discountPercentage,
            tierType,
            tierId
        );
        return (referrer, discountPercentage, rebatePercentage, esRebatePercentage);
    }

    function _collectRebateAndIncreaseCodeStat(
        address _account,
        bytes32 _refCode,
        address _referrer,
        uint256 _fee,
        uint256 _discountFeePercentage,
        TIER_TYPE _tierType,
        uint256 _tierId
    ) internal {
        uint256 feeAfterDiscount;
        uint256 discountFee;
        
        {
            discountFee = _fee * _discountFeePercentage / BASIS_POINTS_DIVISOR;
            feeAfterDiscount = discountFee >= _fee ? 0 : _fee - discountFee;
        }

        uint256 rebateAmount;
        uint256 mintEsROSXAmount;

        {
            (rebateAmount, mintEsROSXAmount) = _collectRebate(
                _account,
                _refCode,
                _referrer,
                feeAfterDiscount,
                _tierType,
                _tierId
            );
        }

        _increaseCodeStat(
            _refCode,
            discountFee,
            rebateAmount,
            mintEsROSXAmount
        );
    }

    function _collectRebate(
        address _account,
        bytes32 _code,
        address _referrer,
        uint256 _feeAfterDiscount, 
        TIER_TYPE _tierType,
        uint256 _tier
    ) internal returns (uint256, uint256) {
        require(address(rUSD) != address(0), "Invalid rUSD");
        require(address(esROSX) != address(0), "Invalid esROSX");
        address recipient = _referrer == address(0) ? settingsManager.getFeeManager() : _referrer;
        require(recipient != address(0), "Invalid recipient");
        uint256 rebatePercentage = _getRebatePercentage(_tierType, _tier);
        uint256 rebateAmount = _feeAfterDiscount == 0 ? 0 : _feeAfterDiscount * rebatePercentage / BASIS_POINTS_DIVISOR;

        if (rebateAmount > 0) {
            IMintable(rUSD).mint(recipient, rebateAmount);
            emit ReferralDelievered(_account, _code, recipient, rebateAmount);
        }

        uint256 mintEsROSXAmount;

        if (_tierType == TIER_TYPE.PREMIUM) {
            uint256 esRebateAmount = _feeAfterDiscount == 0 ? 0 : _feeAfterDiscount * premiumTiers[_tier].esRebatePercentage / BASIS_POINTS_DIVISOR;

            if (esRebateAmount > 0) {
                uint256 rosxPrice = priceManager.getLastPrice(ROSX);
                mintEsROSXAmount = priceManager.fromUSDToToken(ROSX, esRebateAmount, rosxPrice);

                if (mintEsROSXAmount > 0) {
                    try IMintable(esROSX).mint(recipient, mintEsROSXAmount) {
                        emit EscrowRebateDelivered(recipient, esRebateAmount, rosxPrice, mintEsROSXAmount, true, string(new bytes(0)));
                    } catch (bytes memory err) {
                        emit EscrowRebateDelivered(recipient, esRebateAmount, rosxPrice, mintEsROSXAmount, false, _getRevertMsg(err));
                    }
                }
            }
        }

        return (rebateAmount, mintEsROSXAmount);
    }

    function getTier(address _referrer) external view returns (TIER_TYPE, uint256) {
        return _getTier(_referrer);
    }

    function getCodeTier(bytes32 _refCode) external view returns (address, TIER_TYPE, uint256) {
        address referrer = codeOwners[_refCode];
        (TIER_TYPE tierType, uint256 tierId) = _getTier(referrer);
        return (referrer, tierType, tierId);
    }

    function _getTier(address _referrer) internal view returns (TIER_TYPE, uint256) {
        TIER_TYPE tierType = tierOwners[_referrer];
        return (tierType, refTiers[_referrer][uint256(tierType)]);
    }

    function _getDiscountPercentage(TIER_TYPE _tierType, uint256 _tier) internal view returns (uint256) {
        if (_tierType == TIER_TYPE.PREMIUM) {
            return premiumTiers[_tier].discountSharePercentage;
        } else if (_tierType == TIER_TYPE.STANDARD) {
            return standardTiers[_tier].discountSharePercentage;
        } else {
            //Reverse
            revert("Invalid tierType");
        }
    }

    function _getRebatePercentage(TIER_TYPE _tierType, uint256 _tier) internal view returns (uint256) {
        if (_tierType == TIER_TYPE.PREMIUM) {
            return premiumTiers[_tier].rebatePercentage;
        } else if (_tierType == TIER_TYPE.STANDARD) {
            return standardTiers[_tier].rebatePercentage;
        } else {
            //Reverse
            revert("Invalid tierType");
        }
    }

    function increaseCodeStat(address _account, uint256 _discountshareAmount, uint256 _rebateAmount, uint256 _esROSXRebateAmount) external onlyHandler {
        _increaseCodeStat(
            traderReferralCode[_account],
            _discountshareAmount,
            _rebateAmount,
            _esROSXRebateAmount
        );
    }

    function _increaseCodeStat(bytes32 _code, uint256 _discountshareAmount, uint256 _rebateAmount, uint256 _esROSXRebateAmount) internal {
        if (_code != bytes32(0)) {
            ReferralCodeStat storage statistic = codeStats[_code];
            statistic.totalDiscountshare += _discountshareAmount;
            statistic.totalRebate += _rebateAmount;
            statistic.totalEsROSXRebate += _esROSXRebateAmount;
            emit IncreaseCodeStat(_code, _discountshareAmount, _rebateAmount, _esROSXRebateAmount);
        }
    }

    function fixCodeStat(bytes32 _code, uint256 _totalDiscountshare, uint256 _totalRebate, uint256 _totalEsROSXRebate) external onlyAdmin {
        ReferralCodeStat storage statistic = codeStats[_code];
        statistic.totalDiscountshare = _totalDiscountshare;
        statistic.totalRebate = _totalRebate;
        statistic.totalEsROSXRebate = _totalEsROSXRebate;
        emit FixCodeStat(_code, _totalDiscountshare, _totalRebate, _totalEsROSXRebate);
    }

    function getCodeStat(bytes32[] memory code) external view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        require(code.length > 0, "Invalid length");
        uint256[] memory totalRebateArr = new uint256[](code.length);
        uint256[] memory totalDiscountshareArr = new uint256[](code.length);
        uint256[] memory totalEsRebateArr = new uint256[](code.length);

        for (uint256 i = 0; i < code.length; i++) {
            totalRebateArr[i] = codeStats[code[i]].totalRebate;
            totalDiscountshareArr[i] = codeStats[code[i]].totalDiscountshare;
            totalEsRebateArr[i] = codeStats[code[i]].totalEsRebate;
        }

        return (totalRebateArr, totalDiscountshareArr, totalEsRebateArr);
    }
    
    function convertRUSD(
        address _recipient, 
        address _tokenOut, 
        uint256 _amount
    ) external nonReentrant {
        require(settingsManager.isApprovalCollateralToken(_tokenOut) == true, "Invalid tokenOut");
        require(settingsManager.isEnableConvertRUSD(), "Disabled");
        require(!AddressUpgradeable.isContract(msg.sender), "Not allowed");
        require(IERC20Upgradeable(rUSD).balanceOf(msg.sender) > 0, "Insufficient");
        IBurnable(rUSD).burn(msg.sender, _amount);
        bool isStable = settingsManager.isStable(_tokenOut);
        uint256 tokenPrice;
        uint256 amountOut;

        if (isStable) {
            //Force 1-1 if tokenOut is stable
            tokenPrice = PRICE_PRECISION;
            amountOut = priceManager.fromUSDToToken(_tokenOut, _amount, PRICE_PRECISION);
        } else {
            uint256 lastUpdateAt;
            bool isLatestPrice;
            (tokenPrice, lastUpdateAt, isLatestPrice) = priceManager.getLatestSynchronizedPrice(_tokenOut);
            bool isAcceptablePrice = nonStableMaxPriceUpdatedDelay == 0 
                ? isLatestPrice : (block.timestamp - lastUpdateAt) <= nonStableMaxPriceUpdatedDelay;
            require(isAcceptablePrice, "Price oudated, try again");
            amountOut = priceManager.fromUSDToToken(_tokenOut, _amount, tokenPrice);
        }

        require(amountOut > 0, "Zero amountOut");
        vault.takeAssetOut(
            bytes32(0),
            _recipient,
            0,
            _amount,
            _tokenOut,
            tokenPrice
        );
        emit ConvertRUSD(
            _recipient,
            _tokenOut,
            _amount,
            amountOut,
            block.timestamp
        );
    }

    function _validateInternalContracts(address _rUSD, address _settingsManager, address _priceManager, address _vault) internal pure {
        require(_rUSD != address(0) 
            && _settingsManager != address(0) 
            && _priceManager != address(0)
            && _vault != address(0), 
            "Zero impl address"
        );
    }

    /*
    @dev Initialize 3 standard tiers and 5 premium tiers
    */
    function initializeTiers() internal {
        uint256[] memory initStandardTiers = new uint256[](3);
        uint256[] memory initPremiumTiers = new uint256[](5);
        
        for (uint256 i = 0; i < initStandardTiers.length; i++) {
            StandardTier storage tier = standardTiers[i + 1];
            tier.discountSharePercentage = (i + 1) * 5 * BASIS_POINTS_DIVISOR / 100;
            tier.rebatePercentage = (i + 1) * 5 * BASIS_POINTS_DIVISOR / 100;
            tier.isActivate = true;
        }

        for (uint256 i = 0; i < initPremiumTiers.length; i++) {
            PremiumTier storage tier = premiumTiers[i + 1];
            tier.discountSharePercentage = 15 * BASIS_POINTS_DIVISOR / 100;

            if (i == 0) {
                tier.rebatePercentage = 20 * BASIS_POINTS_DIVISOR / 100;
            } else if (i == 1) {
                tier.rebatePercentage = 30 * BASIS_POINTS_DIVISOR / 100;
            } else if (i >= 2) {
                tier.rebatePercentage = 40 * BASIS_POINTS_DIVISOR / 100;
            }

            if (i == 3) {
                tier.esRebatePercentage = 10 * BASIS_POINTS_DIVISOR / 100;
            } else if (i == 4) {
                tier.esRebatePercentage = 20 * BASIS_POINTS_DIVISOR / 100;
            }

            tier.isActivate = true;
        }
    }

    function getCodeUsageLength(address _account) external view returns (uint256) {
        return codeUsage[_account].length();
    }

    function getCodeUsage(address _account) external view returns (bytes32[] memory) {
        return _iteratorCodeUsage(_account);
    }

    function _iteratorCodeUsage(address _account) internal view returns (bytes32[] memory) {
        uint256 length = codeUsage[_account].length();

        if (length == 0) {
            return new bytes32[](0);
        }

        bytes32[] memory codeArr = new bytes32[](length);

        for (uint256 i = 0; i < length; i++) {
            codeArr[i] = codeUsage[_account].at(i);
        }

        return codeArr;
    }

    function getCodeLinkLength(bytes32 _code) external view returns (uint256) {
        return codeLink[_code].length();
    }

    function getCodeLink(bytes32 _code) external view returns (address[] memory) {
        return _iteratorCodeLink(_code);
    }

    function _iteratorCodeLink(bytes32 _code) internal view returns (address[] memory) {
        uint256 length = codeLink[_code].length();

        if (length == 0) {
            return new address[](0);
        }

        address[] memory accountArr = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            accountArr[i] = codeLink[_code].at(i);
        }

        return accountArr;
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        //If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) {
            return "Transaction reverted silently";
        }

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }

        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}
