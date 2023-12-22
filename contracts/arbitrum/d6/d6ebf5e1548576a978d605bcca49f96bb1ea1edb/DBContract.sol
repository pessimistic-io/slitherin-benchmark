// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./IUser.sol";
import "./ILYNKNFT.sol";
import "./OwnableUpgradeable.sol";
import "./IUser.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";


contract DBContract is OwnableUpgradeable {


    /**************************************************************************
     *****  Common fields  ****************************************************
     **************************************************************************/
    address immutable public USDT_TOKEN;

    address public LRT_TOKEN;
    address public AP_TOKEN;
    address public STAKING;
    address public USER_INFO;
    address public LYNKNFT;
    address public STAKING_LYNKNFT;
    address public LISTED_LYNKNFT;
    address public MARKET;
    address public TEAM_ADDR;
    address public operator;

    /**************************************************************************
     *****  AlynNFT fields  ***************************************************
     **************************************************************************/
    uint256[] public mintPrices;
    uint256 public maxMintPerDayPerAddress;
    string public baseTokenURI;
    uint256[][] public attributeLevelThreshold;
    // @Deprecated
    uint256 public maxVAAddPerDayPerToken;

    /**************************************************************************
     *****  Market fields  ****************************************************
     **************************************************************************/
    address[] public acceptTokens;
    uint256 public sellingLevelLimit;
    uint256 public tradingFee;

    /**************************************************************************
     *****  User fields  ******************************************************
     **************************************************************************/
    address public rootAddress;
    uint256[] public directRequirements;
    uint256[] public performanceRequirements;
    uint256[] public socialRewardRates;
    uint256 public contributionRewardThreshold;
    uint256[] public contributionRewardAmounts;
    uint256 public maxInvitationLevel;
    mapping(uint256 => uint256[]) public communityRewardRates;
    uint256 public achievementRewardLevelThreshold;
    uint256 public achievementRewardDurationThreshold;
    uint256[] public achievementRewardAmounts;

    /**************************************************************************
     *****  APToken fields  ***************************************************
     **************************************************************************/
    uint256[][] public sellingPackages;

    uint256 public duration;

    uint256[] public maxVAAddPerDayPerTokens;
    uint256 public performanceThreshold;

    // early bird plan, id range: [startId, endId)
    uint256 public earlyBirdInitCA;
    uint256 public earlyBirdMintStartId;
    uint256 public earlyBirdMintEndId;
    address public earlyBirdMintPayment;
    uint256 public earlyBirdMintPriceInPayment;
    bool public earlyBirdMintEnable;
    bool public commonMintEnable;

    uint256 public wlNum;
    mapping(address => bool) public earlyBirdMintWlOf;

    uint256 public lrtPriceInLYNK;


    address[] public revADDR;

    // v2 
    uint256[][] public mintNode;
    bool public nftMintEnable;

    address public marketAddress;

    /**
     * @dev Throws if called by any account other than the operator.
     */
    modifier onlyOperator() {
        require(operator == _msgSender(), "DBContract: caller is not the operator");
        _;
    }

    constructor(address _usdtToken) {
        USDT_TOKEN = _usdtToken;
    }

    function __DBContract_init(address[] calldata _addresses) public initializer {
        __DBContract_init_unchained(_addresses);
        __Ownable_init();
    }

    function __DBContract_init_unchained(address[] calldata _addresses) private {
        _setAddresses(_addresses);
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setAddresses(address[] calldata _addresses) external onlyOperator {
        _setAddresses(_addresses);
    }


    /**************************************************************************
     *****  AlynNFT Manager  **************************************************
     **************************************************************************/
    function setMintPrices(uint256[] calldata _mintPrices) external onlyOperator {
        require(_mintPrices.length == 3, 'DBContract: length mismatch.');
        delete mintPrices;

        mintPrices = _mintPrices;
    }

    function setMaxMintPerDayPerAddress(uint256 _maxMintPerDayPerAddress) external onlyOperator {
        maxMintPerDayPerAddress = _maxMintPerDayPerAddress;
    }

    function setBaseTokenURI(string calldata _baseTokenURI) external onlyOperator {
        baseTokenURI = _baseTokenURI;
    }

    function setEarlyBirdInitCA(uint256 _earlyBirdInitCA) external onlyOperator {
        earlyBirdInitCA = _earlyBirdInitCA;
    }

    function setEarlyBirdMintIdRange(uint256 _earlyBirdMintStartId, uint256 _earlyBirdMintEndId) external onlyOperator {
        require(_earlyBirdMintEndId > _earlyBirdMintStartId, 'DBContract: invalid id range.');
        earlyBirdMintStartId = _earlyBirdMintStartId;
        earlyBirdMintEndId = _earlyBirdMintEndId;
    }

    function setEarlyBirdMintPrice(address _earlyBirdMintPayment, uint256 _earlyBirdMintPriceInPayment) external onlyOperator {
        require(_earlyBirdMintPayment != address(0), 'DBContract: payment cannot be 0.');
        earlyBirdMintPayment = _earlyBirdMintPayment;
        earlyBirdMintPriceInPayment = _earlyBirdMintPriceInPayment;
    }

    function setSwitch(bool _earlyBirdMintEnable, bool _commonMintEnable) external onlyOperator {
        earlyBirdMintEnable = _earlyBirdMintEnable;
        commonMintEnable = _commonMintEnable;
    }

    function setWlNum(uint256 _wlNum) external onlyOperator {
        // require(wlNum == 0);
        wlNum = _wlNum;
    }

    function setWls(address[] calldata _wls) external onlyOperator {
        for (uint i = 0; i < _wls.length; i++) {
            earlyBirdMintWlOf[_wls[i]] = true;
            if (!IUser(USER_INFO).isValidUser(_wls[i])) {
                IUser(USER_INFO).registerByEarlyPlan(_wls[i], rootAddress);
            }
        }
    }

    /**
     * CA: [100, 500, 1000 ... ]
     */
    function setAttributeLevelThreshold(ILYNKNFT.Attribute _attr, uint256[] calldata _thresholds) external onlyOperator {
        require(uint256(_attr) <= attributeLevelThreshold.length, 'DBContract: length mismatch.');

        for (uint256 index; index < _thresholds.length; index++) {
            if (index > 0) {
                require(_thresholds[index] >= _thresholds[index - 1], 'DBContract: invalid thresholds.');
            }
        }

        if (attributeLevelThreshold.length == uint256(_attr)) {
            attributeLevelThreshold.push(_thresholds);
        } else {
            delete attributeLevelThreshold[uint256(_attr)];
            attributeLevelThreshold[uint256(_attr)] = _thresholds;
        }
    }

    // @Deprecated
    function setMaxVAAddPerDayPerToken(uint256 _maxVAAddPerDayPerToken) external onlyOperator {
        maxVAAddPerDayPerToken = _maxVAAddPerDayPerToken;
    }

    function setMaxVAAddPerDayPerTokens(uint256[] calldata _maxVAAddPerDayPerTokens) external onlyOperator {
        delete maxVAAddPerDayPerTokens;
        maxVAAddPerDayPerTokens = _maxVAAddPerDayPerTokens;
    }

    /**************************************************************************
     *****  Market Manager  ***************************************************
     **************************************************************************/
    function setAcceptToken(address _acceptToken) external onlyOperator {
        uint256 wlLength = acceptTokens.length;
        for (uint256 index; index < wlLength; index++) {
            if (_acceptToken == acceptTokens[index]) return;
        }

        acceptTokens.push(_acceptToken);
    }

    function removeAcceptToken(uint256 _index) external onlyOperator {
        uint256 wlLength = acceptTokens.length;
        if (_index < acceptTokens.length - 1)
            acceptTokens[_index] = acceptTokens[wlLength - 1];
        acceptTokens.pop();
    }

    function setSellingLevelLimit(uint256 _sellingLevelLimit) external onlyOperator {
        sellingLevelLimit = _sellingLevelLimit;
    }

    // e.g. 100% = 1e18
    function setTradingFee(uint256 _tradingFee) external onlyOperator {
        require(_tradingFee <= 1e18, 'DBContract: too large.');
        tradingFee = _tradingFee;
    }

    /**************************************************************************
     *****  User Manager  *****************************************************
     **************************************************************************/
    function setRootAddress(address _rootAddress) external onlyOperator {
        require(_rootAddress != address(0), 'DBContract: root cannot be zero address.');

        rootAddress = _rootAddress;
    }

    function setDirectRequirements(uint256[] calldata _requirements) external onlyOperator {
        require(_requirements.length == uint256(type(IUser.Level).max), 'DBContract: length mismatch.');

        delete directRequirements;
        directRequirements = _requirements;
    }

    function setPerformanceRequirements(uint256[] calldata _requirements) external onlyOperator {
        require(_requirements.length == uint256(type(IUser.Level).max), 'DBContract: length mismatch.');

        delete performanceRequirements;
        performanceRequirements = _requirements;
    }

    function setPerformanceThreshold(uint256 _performanceThreshold) external onlyOperator {
        performanceThreshold = _performanceThreshold;
    }

    // e.g. 100% = 1e18
    function setSocialRewardRates(uint256[] calldata _rates) external onlyOperator {
        require(_rates.length == uint256(type(IUser.Level).max) + 1, 'DBContract: length mismatch.');

        delete socialRewardRates;
        for (uint256 index; index < _rates.length; index++) {
            require(_rates[index] <= 1e18, 'DBContract: too large.');
        }

        socialRewardRates = _rates;
    }

    function setContributionRewardThreshold(uint256 _contributionRewardThreshold) external onlyOperator {
        contributionRewardThreshold = _contributionRewardThreshold;
    }

    function setContributionRewardAmounts(uint256[] calldata _amounts) external onlyOperator {
        require(_amounts.length == uint256(type(IUser.Level).max) + 1, 'DBContract: length mismatch.');

        delete contributionRewardAmounts;
        contributionRewardAmounts = _amounts;
    }

    function setCommunityRewardRates(IUser.Level _level, uint256[] calldata _rates) external onlyOperator {
        uint256 levelUint = uint256(_level);

        delete communityRewardRates[levelUint];

        if (_rates.length > maxInvitationLevel) {
            maxInvitationLevel = _rates.length;
        }
        communityRewardRates[levelUint] = _rates;
    }

    function setAchievementRewardDurationThreshold(uint256 _achievementRewardDurationThreshold) external onlyOperator {
        achievementRewardDurationThreshold = _achievementRewardDurationThreshold;
    }

    function setAchievementRewardLevelThreshold(uint256 _achievementRewardLevelThreshold) external onlyOperator {
        achievementRewardLevelThreshold = _achievementRewardLevelThreshold;
    }

    function setAchievementRewardAmounts(uint256[] calldata _amounts) external onlyOperator {
        require(_amounts.length == uint256(type(IUser.Level).max) + 1, 'DBContract: length mismatch.');

        delete achievementRewardAmounts;
        achievementRewardAmounts = _amounts;
    }

    /**************************************************************************
     *****  APToken Manager  **************************************************
     **************************************************************************/
    function setSellingPackage(uint256[][] calldata _packages) external onlyOperator {
        delete sellingPackages;

        for (uint256 index; index < _packages.length; index++) {
            require(_packages[index].length == 3, 'DBContract: length mismatch.');

            sellingPackages.push(_packages[index]);
        }
    }

    function setDuration(uint256 _duration) external onlyOperator {
        duration = _duration;
    }

    function setLRTPriceInLYNK(uint256 _lrtPriceInLYNK) external onlyOperator {
        lrtPriceInLYNK = _lrtPriceInLYNK;
    }

    /**************************************************************************
     *****  public view  ******************************************************
     **************************************************************************/
    function calcTokenLevel(uint256 _tokenId) external view returns (uint256 level) {
        return _calcTokenLevel(_tokenId);
    }

    function calcLevel(ILYNKNFT.Attribute _attr, uint256 _point) external view returns (uint256 level, uint256 overflow) {
        return _calcLevel(_attr, _point);
    }

    function acceptTokenLength() external view returns (uint256) {
        return acceptTokens.length;
    }

    function isAcceptToken(address _token) external view returns (bool) {
        uint256 wlLength = acceptTokens.length;
        for (uint256 index; index < wlLength; index++) {
            if (_token == acceptTokens[index]) return true;
        }

        return false;
    }

    function packageLength() external view returns (uint256) {
        return sellingPackages.length;
    }

    function packageByIndex(uint256 _index) external view returns (uint256[] memory) {
        require(_index < sellingPackages.length, 'DBContract: index out of bounds.');

        return sellingPackages[_index];
    }

    function communityRewardRate(IUser.Level _level, uint256 _invitationLevel) external view returns (uint256) {
        if (communityRewardRates[uint256(_level)].length > _invitationLevel) {
            return communityRewardRates[uint256(_level)][_invitationLevel];
        }

        return 0;
    }

    function hasAchievementReward(uint256 _nftId) external view returns (bool) {
        return _calcTokenLevel(_nftId) >= achievementRewardLevelThreshold;
    }

    function _calcTokenLevel(uint256 _tokenId) private view returns (uint256 level) {
        require(ILYNKNFT(LYNKNFT).exists(_tokenId), 'DBContract: invalid token ID.');

        uint256[] memory _nftInfo = ILYNKNFT(LYNKNFT).nftInfoOf(_tokenId);
        for (uint256 index; index < uint256(type(ILYNKNFT.Attribute).max) + 1; index++) {
            (uint256 levelSingleAttr,) = _calcLevel(ILYNKNFT.Attribute(index), _nftInfo[index]);
            if (index == 0 || levelSingleAttr < level) {
                level = levelSingleAttr;
            }
        }

        return level;
    }

    function _calcLevel(ILYNKNFT.Attribute _attr, uint256 _point) private view returns (uint256 level, uint256 overflow) {
        level = 0;
        overflow = _point;
        uint256 thresholdLength = attributeLevelThreshold[uint256(_attr)].length;
        for (uint256 index; index < thresholdLength; index++) {
            if (_point >= attributeLevelThreshold[uint256(_attr)][index]) {
                level = index + 1;
                overflow = _point - attributeLevelThreshold[uint256(_attr)][index];
            } else {
                break;
            }
        }
        return (level, overflow);
    }

    function _setAddresses(address[] calldata _addresses) private {
        require(_addresses.length == 9, 'DBContract: addresses length mismatch.');

        LRT_TOKEN           = _addresses[0];
        AP_TOKEN            = _addresses[1];
        STAKING             = _addresses[2];
        LYNKNFT             = _addresses[3];
        STAKING_LYNKNFT     = _addresses[4];
        LISTED_LYNKNFT      = _addresses[5];
        MARKET              = _addresses[6];
        USER_INFO           = _addresses[7];
        TEAM_ADDR           = _addresses[8];
    }

    function mintPricesNum() external view returns (uint256) {
        return mintPrices.length;
    }

    function attributeLevelThresholdNum() external view returns (uint256) {
        return attributeLevelThreshold.length;
    }

    function attributeLevelThresholdNumByIndex(uint256 index) external view returns (uint256) {
        return attributeLevelThreshold.length > index ? attributeLevelThreshold[index].length : 0;
    }

    function directRequirementsNum() external view returns (uint256) {
        return directRequirements.length;
    }

    function performanceRequirementsNum() external view returns (uint256) {
        return performanceRequirements.length;
    }

    function socialRewardRatesNum() external view returns (uint256) {
        return socialRewardRates.length;
    }

    function contributionRewardAmountsNum() external view returns (uint256) {
        return contributionRewardAmounts.length;
    }

    function communityRewardRatesNumByLevel(IUser.Level _level) external view returns (uint256) {
        return communityRewardRates[uint256(_level)].length;
    }

    function achievementRewardAmountsNum() external view returns (uint256) {
        return achievementRewardAmounts.length;
    }

    function maxVAAddPerDayPerTokensNum() external view returns (uint256) {
        return maxVAAddPerDayPerTokens.length;
    }

    function maxVAAddPerDayByTokenId(uint256 _tokenId) external view returns (uint256) {
        uint256 tokenLevel = _calcTokenLevel(_tokenId);
        if (tokenLevel > maxVAAddPerDayPerTokens.length - 1) return 0;

        return maxVAAddPerDayPerTokens[tokenLevel];
    }

    function earlyBirdMintIdRange() external view returns (uint256, uint256) {
        return (earlyBirdMintStartId, earlyBirdMintEndId);
    }

    function earlyBirdMintPrice() external view returns (address, uint256) {
        return (earlyBirdMintPayment, earlyBirdMintPriceInPayment);
    }

    function revADDRNum() external view returns (uint256) {
        return revADDR.length;
    }

    function isRevAddr(address _adr) external view returns (bool) {
        for (uint i = 0; i < revADDR.length;i++) {
            if(revADDR[i] == _adr){
                return true;
            }
        }
        return false;
    }

    function setRevAddr(address[] calldata _addr_ls) external onlyOperator {

        delete revADDR;
        //uint max = uint256(type(IUser.REV_TYPE).max);
        require(_addr_ls.length ==  7 , 'RevAddr length mismatch.');
        for (uint i = 0; i < 7;i++) {
            revADDR.push(_addr_ls[i]);
        }
    }

    //v2
    function setMintNode(uint256[][] calldata _mintNode) external onlyOperator {
        delete mintNode;
        for (uint256 index; index < _mintNode.length; index++) {
            require(_mintNode[index].length == 4, 'DBContract: length mismatch.');
            mintNode.push(_mintNode[index]);
        }
    }
    function nodeByIndex(uint256 _index) external view returns (uint256[] memory) {
        require(_index < mintNode.length, 'DBContract: index out of bounds.');

        return mintNode[_index];
    }
    function setNFTMintEnable(bool _nftMintEnable) external onlyOperator {
        nftMintEnable = _nftMintEnable;
    }
    
    function seMarketAddress(address _market) external onlyOperator {
        marketAddress = _market;
    }

}

