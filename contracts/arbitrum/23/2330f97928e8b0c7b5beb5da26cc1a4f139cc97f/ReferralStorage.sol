// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./SafeMath.sol";

import "./Governable.sol";
import "./ITimelock.sol";

import "./IReferralStorage.sol";

contract DTReferralStorage is Governable, IReferralStorage {
    using SafeMath for uint256;

    struct Tier {
        uint256 totalRebate; // e.g. 2400 for 24%
        uint256 discountShare; // 5000 for 50%/50%, 7000 for 30% rebates/70% discount
    }

    uint256 public constant BASIS_POINTS = 10000;

    mapping(address => uint256) public referrerDiscountShares; // to override default value in tier
    mapping(address => uint256) public referrerTiers; // link between user <> tier
    mapping(uint256 => Tier) public tiers;

    mapping(address => bool) public isHandler;

    mapping(bytes32 => address) public codeOwners;
    mapping(address => bytes32) public traderReferralCodes;
    mapping(address => bytes32) public userCodes;

    event SetHandler(address handler, bool isActive);
    event SetTraderReferralCode(address account, bytes32 code);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetReferrerDiscountShare(address referrer, uint256 discountShare);
    event RegisterCode(address account, bytes32 code);
    event SetCodeOwner(address account, address newAccount, bytes32 code);
    event GovSetCodeOwner(bytes32 code, address newAccount);

    modifier onlyHandler() {
        require(isHandler[msg.sender], "DTReferralStorage: forbidden");
        _;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function setTier(
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external onlyGov {
        require(
            _totalRebate <= BASIS_POINTS,
            "DTReferralStorage: invalid totalRebate"
        );
        require(
            _discountShare <= BASIS_POINTS,
            "DTReferralStorage: invalid discountShare"
        );

        Tier memory tier = tiers[_tierId];
        tier.totalRebate = _totalRebate;
        tier.discountShare = _discountShare;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _totalRebate, _discountShare);
    }

    function setReferrerTier(address _referrer, uint256 _tierId)
        external
        onlyGov
    {
        referrerTiers[_referrer] = _tierId;
        emit SetReferrerTier(_referrer, _tierId);
    }

    function setReferrerDiscountShare(uint256 _discountShare) external {
        require(
            _discountShare <= BASIS_POINTS,
            "DTReferralStorage: invalid discountShare"
        );

        referrerDiscountShares[msg.sender] = _discountShare;
        emit SetReferrerDiscountShare(msg.sender, _discountShare);
    }

    function setTraderReferralCode(address _account, bytes32 _code)
        external
        override
        onlyHandler
    {
        _setTraderReferralCode(_account, _code);
    }

    function setTraderReferralCodeByUser(bytes32 _code) external {
        _setTraderReferralCode(msg.sender, _code);
    }

    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "DTReferralStorage: invalid _code");
        require(
            codeOwners[_code] == address(0),
            "DTReferralStorage: code already exists"
        );

        codeOwners[_code] = msg.sender;
        userCodes[msg.sender] = _code;
        emit RegisterCode(msg.sender, _code);
    }

    function setCodeOwner(bytes32 _code, address _newAccount) external {
        require(_code != bytes32(0), "DTReferralStorage: invalid _code");

        address account = codeOwners[_code];
        require(msg.sender == account, "DTReferralStorage: forbidden");

        codeOwners[_code] = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    function govSetCodeOwner(bytes32 _code, address _newAccount)
        external
        onlyGov
    {
        require(_code != bytes32(0), "DTReferralStorage: invalid _code");

        codeOwners[_code] = _newAccount;
        emit GovSetCodeOwner(_code, _newAccount);
    }

    function getTraderReferralInfo(address _account)
        external
        view
        override
        returns (bytes32, address)
    {
        bytes32 code = traderReferralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    function _setTraderReferralCode(address _account, bytes32 _code) private {
        traderReferralCodes[_account] = _code;
        emit SetTraderReferralCode(_account, _code);
    }
}

