// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./IStakeable.sol";
import "./IReferral.sol";
import "./Errors.sol";
import "./FixedPoint.sol";
import "./EnumerableMap.sol";
import "./OwnableUpgradeable.sol";
import "./SafeCast.sol";

contract Referrals is OwnableUpgradeable, IReferral {
  using FixedPoint for uint256;
  using SafeCast for uint256;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  struct RebatePct {
    uint64 referralRebatePct;
    uint64 referredRebatePct;
  }

  struct ReferralSetting {
    uint64 max;
    uint64 count;
  }

  RebatePct public defaultRebatePct;

  EnumerableMap.AddressToUintMap internal _ugpBoost;

  mapping(address => ReferralSetting) internal _referralSettings;
  mapping(address => mapping(uint64 => bytes32)) public referralCodes;
  mapping(address => bytes32) public referredBy;
  mapping(bytes32 => address) public referrer;
  mapping(bytes32 => RebatePct) internal _rebatePct;

  event SetDefaultRebatePctEvent(
    uint256 referralRebatePct,
    uint256 referredRebatePct
  );
  event SetRebatePctEvent(
    bytes32 indexed referralCode,
    uint256 referralRebatePct,
    uint256 referredRebatePct
  );
  event CreateReferralCodeEvent(
    address indexed referrer,
    bytes32 indexed referralCode
  );
  event RemoveReferralCodeEvent(
    address indexed referrer,
    bytes32 indexed referralCode
  );
  event UseReferralCodeEvent(
    address indexed referee,
    bytes32 indexed referralCode
  );
  event SetUGPBoostEvent(address indexed ugpAddress, uint256 ugpBoost);

  function initialize(
    address _owner,
    uint64 _referralRebatePct,
    uint64 _referredRebatePct
  ) external initializer {
    __Ownable_init();
    _transferOwnership(_owner);

    defaultRebatePct = RebatePct(_referralRebatePct, _referredRebatePct);
    emit SetDefaultRebatePctEvent(_referralRebatePct, _referredRebatePct);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier validRebatePct(
    uint256 _referralRebatePct,
    uint256 _referredRebatePct
  ) {
    _require(
      _referralRebatePct >= 0 && _referralRebatePct <= 1e18,
      Errors.INVALID_SHARE
    );
    _require(
      _referredRebatePct >= 0 && _referredRebatePct <= 1e18,
      Errors.INVALID_SHARE
    );
    _require(
      _referralRebatePct + _referredRebatePct <= 1e18,
      Errors.INVALID_SHARE
    );
    _;
  }

  // governance functions

  function setDefaultRebatePct(
    uint64 _referralRebatePct,
    uint64 _referredRebatePct
  ) external onlyOwner validRebatePct(_referralRebatePct, _referredRebatePct) {
    defaultRebatePct = RebatePct(_referralRebatePct, _referredRebatePct);
    emit SetDefaultRebatePctEvent(_referralRebatePct, _referredRebatePct);
  }

  function setRebatePct(
    bytes32 referralCode,
    uint64 _referralRebatePct,
    uint64 _referredRebatePct
  ) external onlyOwner validRebatePct(_referralRebatePct, _referredRebatePct) {
    _rebatePct[referralCode] = RebatePct(
      _referralRebatePct,
      _referredRebatePct
    );
    emit SetRebatePctEvent(
      referralCode,
      _referralRebatePct,
      _referredRebatePct
    );
  }

  function setMaxReferralCodes(address creator, uint64 max) external onlyOwner {
    _referralSettings[creator].max = max;
  }

  function setUGPBoost(
    address ugpAddress,
    uint256 ugpBoost
  ) external onlyOwner {
    _ugpBoost.set(ugpAddress, ugpBoost);
    emit SetUGPBoostEvent(ugpAddress, ugpBoost);
  }

  // priviliged functions

  function removeReferralCode(bytes32 referralCode) external {
    _require(
      msg.sender == referrer[referralCode] || msg.sender == owner(),
      Errors.INVALID_REFERRAL_CODE
    );
    _removeReferralCode(referralCode);
  }

  // external functions

  function getUGPBoost(address ugpAddress) external view returns (uint256) {
    return _ugpBoost.get(ugpAddress);
  }

  function getReferralSetting(
    address creator
  ) external view returns (ReferralSetting memory setting) {
    setting = _referralSettings[creator];
    if (setting.max == 0) {
      setting.max = 1;
      if (referralCodes[creator][0] != bytes32(0)) {
        setting.count = 1;
      }
    }
  }

  function getRebatePct(
    bytes32 referralCode
  ) external view returns (RebatePct memory) {
    return _getRebatePct(referralCode);
  }

  function useReferralCode(bytes32 referralCode) external {
    _require(
      referrer[referralCode] != address(0),
      Errors.INVALID_REFERRAL_CODE
    );
    referredBy[msg.sender] = referralCode;
    emit UseReferralCodeEvent(msg.sender, referralCode);
  }

  function createReferralCode(bytes32 referralCode) external {
    _require(
      referrer[referralCode] == address(0),
      Errors.INVALID_REFERRAL_CODE
    );
    ReferralSetting memory setting = _referralSettings[msg.sender];
    if (setting.max == 0) {
      setting.max += 1;
    }
    setting.count += 1;

    _require(setting.max >= setting.count, Errors.EXCEED_MAX_REFERRAL_CODES);

    uint256 code = uint256(referralCode);
    uint8 len = 0;
    for (uint8 i = 0; i < 32; ++i) {
      uint256 b = code & uint256(0xff);
      bool valid = (i > 0 || b > 0) &&
        (b == 0 || (b >= 48 && b <= 57) || (b >= 97 && b <= 122));
      _require(valid, Errors.INVALID_REFERRAL_CODE);
      code = code >> 8;
      if (b == 0) {
        _require(code == 0, Errors.INVALID_REFERRAL_CODE);
      } else {
        len++;
      }
    }
    _require(len >= 3, Errors.INVALID_REFERRAL_CODE);

    _referralSettings[msg.sender] = setting;
    referralCodes[msg.sender][setting.count - 1] = referralCode;
    referrer[referralCode] = msg.sender;
    emit CreateReferralCodeEvent(msg.sender, referralCode);
  }

  function getReferral(
    address _user
  ) external view override returns (Referral memory referral) {
    if (referredBy[_user] == bytes32(0)) {
      return Referral(0, 0, address(0), bytes32(0));
    } else {
      return _getReferralByCode(referredBy[_user]);
    }
  }

  function getReferralByCode(
    bytes32 referralCode
  ) external view override returns (Referral memory referral) {
    return _getReferralByCode(referralCode);
  }

  // internal functions

  function _removeReferralCode(bytes32 referralCode) internal {
    address _referrer = referrer[referralCode];
    _require(_referrer != address(0), Errors.INVALID_REFERRAL_CODE);

    ReferralSetting memory setting = _referralSettings[_referrer];

    uint64 index = 0;
    for (uint64 i = 0; i < setting.count; ++i) {
      if (referralCodes[_referrer][index] == referralCode) {
        index = i;
      }
    }

    if (index + 1 == setting.count) {
      delete referralCodes[_referrer][index];
    } else {
      referralCodes[_referrer][index] = referralCodes[_referrer][
        setting.count - 1
      ];
      delete referralCodes[_referrer][setting.count - 1];
    }
    _referralSettings[_referrer].count = setting.count - 1;

    delete _rebatePct[referralCode];
    delete referrer[referralCode];
    emit RemoveReferralCodeEvent(_referrer, referralCode);
  }

  function _getReferralByCode(
    bytes32 referralCode
  ) internal view returns (Referral memory referral) {
    address _referrer = referrer[referralCode];

    RebatePct memory _rebate = _getRebatePct(referralCode);

    uint256 _length = _ugpBoost.length();
    for (uint256 i = 0; i < _length; ++i) {
      (address ugpAddress, uint256 ugpBoost) = _ugpBoost.at(i);
      if (IStakeable(ugpAddress).hasStake(_referrer))
        return
          Referral(
            _rebate.referredRebatePct,
            uint256(_rebate.referralRebatePct)
              .mulDown(ugpBoost.add(uint256(1e18)))
              .toUint64(),
            _referrer,
            referralCode
          );
    }

    return
      Referral(
        _rebate.referredRebatePct,
        _rebate.referralRebatePct,
        _referrer,
        referralCode
      );
  }

  function _getRebatePct(
    bytes32 referralCode
  ) internal view returns (RebatePct memory _rebate) {
    _rebate = _rebatePct[referralCode];
    if (_rebate.referralRebatePct == 0 && _rebate.referredRebatePct == 0) {
      _rebate = defaultRebatePct;
    }
  }
}

