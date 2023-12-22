// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "./SafeMath.sol";
import "./IManager.sol";
import "./IERC20.sol";
import "./ITradeToken.sol";
import "./IMarket.sol";

contract InviteManager {
    using SafeMath for uint256;
    address public manager;                                 //Manager address

    uint256 public constant RATE_PRECISION = 1e6;
    uint256 public constant AMOUNT_PRECISION = 1e20;               // amount decimal 1e20

    struct Tier {
        uint256 totalRebate;                                // e.g. 2400 for 24%
        uint256 discountShare;                              // 5000 for 50%/50%, 7000 for 30% rebates/70% discount
        uint256 upgradeTradeAmount;                         //upgrade trade amount
    }

    mapping(uint256 => Tier) public tiers;                  //level => Tier

    struct ReferralCode {
        address owner;
        uint256 registerTs;
        uint256 tierId;
    }

    mapping(bytes32 => ReferralCode) public codeOwners;     //referralCode => owner
    mapping(address => bytes32) public traderReferralCodes; //account => referralCode

    address public upgradeToken;
    address public tradeToken;
    address public inviteToken;
    uint256 public tradeTokenDecimals;
    uint256 public inviteTokenDecimals;
    bool public isUTPPaused = true;
    bool public isURPPaused = true;
    mapping(address => uint256) public tradeTokenBalance;
    mapping(address => uint256) public inviteTokenBalance;

    event SetTraderReferralCode(address account, bytes32 code);
    event RegisterCode(address account, bytes32 code, uint256 time);
    event SetCodeOwner(address account, address newAccount, bytes32 code);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare, uint256 upgradeTradeAmount);
    event SetReferrerTier(bytes32 code, uint256 tierId);
    event ClaimInviteToken(address account, uint256 amount);
    event ClaimTradeToken(address account, uint256 amount);
    event AddTradeTokenBalance(address account, uint256 amount);
    event AddInviteTokenBalance(address account, uint256 amount);
    event SetUpgradeToken(address token);
    event SetTradeToken(address tradeToken, uint256 decimals);
    event SetInviteToken(address inviteToken, uint256 decimals);
    event UpdateTradeValue(address account, uint256 value);
    event IsUTPPausedSettled(bool isUTPPaused);
    event IsURPPausedSettled(bool isURPPaused);

    constructor(address _manager) {
        require(_manager != address(0), "InviteManager: manager is zero address");
        manager = _manager;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "InviteManager: Must be controller");
        _;
    }

    modifier onlyRouter() {
        require(IManager(manager).checkRouter(msg.sender), "InviteManager: Must be router");
        _;
    }

    modifier onlyMarket(){
        require(IManager(manager).checkMarket(msg.sender), "InviteManager: no permission!");
        _;
    }

    modifier onlyPool(){
        require(IManager(manager).checkPool(msg.sender), "InviteManager: Must be pool!");
        _;
    }

    function setIsUTPPaused(bool _isUTPPaused) external onlyController {
        isUTPPaused = _isUTPPaused;
        emit IsUTPPausedSettled(_isUTPPaused);
    }

    function setIsURPPaused(bool _isURPPaused) external onlyController {
        isURPPaused = _isURPPaused;
        emit IsURPPausedSettled(_isURPPaused);
    }

    function setUpgradeToken(address _token) external onlyController {
        require(_token != address(0), "InviteManager: upgradeToken is zero address");
        upgradeToken = _token;
        emit SetUpgradeToken(_token);
    }

    function setTradeToken(address _tradeToken) external onlyController {
        require(_tradeToken != address(0), "InviteManager: tradeToken is zero address");
        tradeToken = _tradeToken;
        tradeTokenDecimals = IERC20(_tradeToken).decimals();
        emit SetTradeToken(_tradeToken, tradeTokenDecimals);
    }

    function setInviteToken(address _inviteToken) external onlyController {
        require(_inviteToken != address(0), "InviteManager: inviteToken is zero address");
        inviteToken = _inviteToken;
        inviteTokenDecimals = IERC20(_inviteToken).decimals();
        emit SetInviteToken(_inviteToken, inviteTokenDecimals);
    }

    function setTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare, uint256 _upgradeTradeAmount) external onlyController {
        require(_totalRebate <= RATE_PRECISION, "InviteManager: invalid totalRebate");
        require(_discountShare <= RATE_PRECISION, "InviteManager: invalid discountShare");

        Tier memory tier = tiers[_tierId];
        tier.totalRebate = _totalRebate;
        tier.discountShare = _discountShare;
        tier.upgradeTradeAmount = _upgradeTradeAmount;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _totalRebate, _discountShare, _upgradeTradeAmount);
    }

    function setReferrerTier(bytes32 _code, uint256 _tierId) external onlyController {
        codeOwners[_code].tierId = _tierId;
        emit SetReferrerTier(_code, _tierId);
    }

    function upgradeReferrerTierByOwner(bytes32 _code) external {
        require(codeOwners[_code].owner == msg.sender, "InviteManager: invalid owner");
        require(IERC20(upgradeToken).balanceOf(msg.sender) >= tiers[codeOwners[_code].tierId].upgradeTradeAmount, "InviteManager: insufficient balance");

        IERC20(upgradeToken).transferFrom(msg.sender, address(0x000000000000000000000000000000000000dEaD), tiers[codeOwners[_code].tierId].upgradeTradeAmount);

        uint256 _tierId = codeOwners[_code].tierId.add(1);
        require(tiers[_tierId].totalRebate > 0, "InviteManager: invalid tierId");

        codeOwners[_code].tierId = _tierId;
        emit SetReferrerTier(_code, _tierId);
    }


    /// @notice set trader referral code, only router can call
    /// @param _account account address
    /// @param _code referral code
    function setTraderReferralCode(address _account, bytes32 _code) external onlyRouter {
        if (_code != bytes32(0) && traderReferralCodes[_account] != _code && codeOwners[_code].owner != _account) {
            traderReferralCodes[_account] = _code;
            emit SetTraderReferralCode(_account, _code);
        }
    }

    /// @notice set trader referral code, user can call
    /// @param _code referral code
    function setTraderReferralCodeByUser(bytes32 _code) external {
        require(_code != bytes32(0) && traderReferralCodes[msg.sender] != _code && codeOwners[_code].owner != msg.sender, "InviteManager: invalid _code");
        traderReferralCodes[msg.sender] = _code;
        emit SetTraderReferralCode(msg.sender, _code);

    }

    /// @notice register referral code
    /// @param _code referral code
    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "InviteManager: invalid _code");
        require(codeOwners[_code].owner == address(0), "InviteManager: code already exists");

        codeOwners[_code].owner = msg.sender;
        codeOwners[_code].registerTs = block.timestamp;
        codeOwners[_code].tierId = 0;
        emit RegisterCode(msg.sender, _code, codeOwners[_code].registerTs);
    }

    /// @notice set code owner, only owner can call
    /// @param _code referral code
    /// @param _newAccount new account address
    function setCodeOwnerBySystem(bytes32 _code, address _newAccount) external onlyController {
        require(_code != bytes32(0), "InviteManager: invalid _code");
        codeOwners[_code].owner = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }


    /// @notice set code owner, only owner can call
    /// @param _code referral code
    /// @param _newAccount new account address
    function setCodeOwner(bytes32 _code, address _newAccount) external {
        require(_code != bytes32(0), "InviteManager: invalid _code");

        address account = codeOwners[_code].owner;
        require(msg.sender == account, "InviteManager: forbidden");

        codeOwners[_code].owner = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    /// @notice get referral info
    /// @param _codes referral code[]
    function getCodeOwners(bytes32[] memory _codes) public view returns (address[] memory) {
        address[] memory owners = new address[](_codes.length);

        for (uint256 i = 0; i < _codes.length; i++) {
            bytes32 code = _codes[i];
            owners[i] = codeOwners[code].owner;
        }

        return owners;
    }

    function getReferrerCodeByTaker(address _taker) public view returns (bytes32 _code, address _codeOwner, uint256 _takerDiscountRate, uint256 _inviteRate) {
        _code = traderReferralCodes[_taker];
        _codeOwner = codeOwners[_code].owner;
        if (_codeOwner == address(0)) {
            return (_code, address(0), 0, 0);
        }
        _takerDiscountRate = tiers[codeOwners[_code].tierId].discountShare;
        _inviteRate = tiers[codeOwners[_code].tierId].totalRebate;
    }

    function addTradeTokenBalance(address _account, uint256 _amount) internal {
        tradeTokenBalance[_account] = tradeTokenBalance[_account].add(_amount);
        emit AddTradeTokenBalance(_account, _amount);
    }

    function addInviteTokenBalance(address _account, uint256 _amount) internal {
        inviteTokenBalance[_account] = inviteTokenBalance[_account].add(_amount);
        emit AddInviteTokenBalance(_account, _amount);
    }

    function claimInviteToken(address _account) external {
        uint256 amount = inviteTokenBalance[_account];
        require(amount > 0, "InviteManager: no invite token to claim");
        inviteTokenBalance[_account] = 0;
        ITradeToken(inviteToken).mint(_account, amount);
        emit ClaimInviteToken(_account, amount);
    }

    function claimTradeToken(address _account) external {
        uint256 amount = tradeTokenBalance[_account];
        require(amount > 0, "InviteManager: no trade token to claim");
        tradeTokenBalance[_account] = 0;
        ITradeToken(tradeToken).mint(_account, amount);
        emit ClaimTradeToken(_account, amount);
    }

    function updateTradeValue(uint8 _marketType, address _taker, address _inviter, uint256 _tradeValue) external onlyMarket {
        if (_marketType == 0 || _marketType == 1) {
            if (_inviter != address(0) && !isURPPaused) addInviteTokenBalance(_inviter, _tradeValue.mul(10 ** inviteTokenDecimals).div(AMOUNT_PRECISION));
            if (!isUTPPaused) addTradeTokenBalance(_taker, _tradeValue.mul(10 ** tradeTokenDecimals).div(AMOUNT_PRECISION));
            emit UpdateTradeValue(_taker, _tradeValue);
        }
    }
}

