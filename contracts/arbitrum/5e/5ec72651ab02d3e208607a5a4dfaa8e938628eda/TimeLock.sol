// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ITimeLock.sol";
import "./Errors.sol";
import "./ERC20Fixed.sol";
import {ERC20} from "./ERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";

contract TimeLock is
  ITimeLock,
  ReentrancyGuardUpgradeable,
  OwnableUpgradeable,
  AccessControlUpgradeable,
  PausableUpgradeable
{
  using ERC20Fixed for ERC20;

  bytes32 public constant APPROVED_ROLE = keccak256("APPROVED_ROLE");
  bytes32 public constant EMERGENCY_ADMIN_ROLE =
    keccak256("EMERGENCY_ADMIN_ROLE");

  address public restoreAddress;
  uint48 public releaseDelay;
  uint256 public agreementCount;
  mapping(uint256 => Agreement) public agreements;
  mapping(address => mapping(TimeLockDataTypes.AgreementContext => mapping(address => uint))) // user => agreementContext => asset => agreementId
    public agreementsByUser;

  event AgreementCreatedEvent(
    uint256 indexed agreementId,
    address indexed beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext,
    address indexed asset,
    uint256 amount,
    uint48 releaseTime
  );

  event AgreementUpdatedEvent(
    uint256 indexed agreementId,
    address indexed beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext,
    address indexed asset,
    uint256 amount,
    uint48 releaseTime
  );

  event AgreementClaimedEvent(
    uint256 indexed agreementId,
    address indexed beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext,
    address indexed asset,
    uint256 amount,
    uint48 releaseTime
  );

  event AgreementFulfilledEvent(
    uint256 indexed agreementId,
    address indexed beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext,
    address indexed asset,
    uint256 amount,
    uint48 releaseTime
  );

  event AgreementRestoredEvent(
    uint256 indexed agreementId,
    address indexed beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext,
    address indexed asset,
    uint256 amount,
    uint48 releaseTime
  );

  event AgreementFrozenEvent(uint256 indexed agreementId, bool value);

  event SetReleaseDelayEvent(uint48 releaseDelay);

  event SetRestoreAddressEvent(address restoreAddress);

  event FreezeAll(bool value);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _owner,
    uint48 _releaseDelay,
    address _restoreAddress
  ) external initializer {
    __AccessControl_init();
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();

    _transferOwnership(_owner);
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(EMERGENCY_ADMIN_ROLE, _owner);

    releaseDelay = _releaseDelay;
    restoreAddress = _restoreAddress;
  }

  // governance functions

  function pause() external onlyOwner {
    _pause();
    emit FreezeAll(true);
  }

  function unpause() external onlyOwner {
    _unpause();
    emit FreezeAll(false);
  }

  function setReleaseDelay(uint48 _releaseDelay) external onlyOwner {
    releaseDelay = _releaseDelay;
    emit SetReleaseDelayEvent(releaseDelay);
  }

  function setRestoreAddress(address _restoreAddress) external onlyOwner {
    restoreAddress = _restoreAddress;
    emit SetRestoreAddressEvent(restoreAddress);
  }

  function restore(
    uint256[] calldata agreementIds
  ) external nonReentrant onlyOwner {
    Agreement memory agreement;
    for (uint256 index = 0; index < agreementIds.length; ++index) {
      agreement = agreements[agreementIds[index]];
      _require(agreement.isFrozen, Errors.AGREEMENT_NOT_FROZEN);
      delete agreements[agreementIds[index]];
      delete agreementsByUser[agreement.beneficiary][
        agreement.agreementContext
      ][agreement.asset];

      emit AgreementRestoredEvent(
        agreementIds[index],
        agreement.beneficiary,
        agreement.agreementContext,
        agreement.asset,
        agreement.amount,
        agreement.releaseTime
      );

      ERC20(agreement.asset).transferFixed(restoreAddress, agreement.amount);
    }
  }

  // privileged functions

  function freezeAllAgreements() external onlyRole(EMERGENCY_ADMIN_ROLE) {
    _pause();
    emit FreezeAll(true);
  }

  function unfreezeAllAgreements() external onlyRole(EMERGENCY_ADMIN_ROLE) {
    _unpause();
    emit FreezeAll(false);
  }

  function createAgreement(
    address asset,
    uint256 amount,
    address beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext
  ) external nonReentrant onlyRole(APPROVED_ROLE) {
    _createAgreement(asset, amount, beneficiary, agreementContext);
  }

  function fulfill(
    uint256[] calldata agreementIds
  ) external nonReentrant onlyOwner whenNotPaused {
    Agreement memory agreement;
    for (uint256 index = 0; index < agreementIds.length; ++index) {
      agreement = agreements[agreementIds[index]];
      if (agreement.amount > 0) {
        delete agreements[agreementIds[index]];
        delete agreementsByUser[agreement.beneficiary][
          agreement.agreementContext
        ][agreement.asset];

        emit AgreementFulfilledEvent(
          agreementIds[index],
          agreement.beneficiary,
          agreement.agreementContext,
          agreement.asset,
          agreement.amount,
          agreement.releaseTime
        );

        ERC20(agreement.asset).transferFixed(
          agreement.beneficiary,
          agreement.amount
        );
      }
    }
  }

  function freezeAgreement(
    uint256 agreementId
  ) external onlyRole(EMERGENCY_ADMIN_ROLE) {
    _freezeAgreement(agreementId);
  }

  function freezeAgreements(
    uint256[] calldata agreementIds
  ) external onlyRole(EMERGENCY_ADMIN_ROLE) {
    for (uint256 index = 0; index < agreementIds.length; ++index) {
      _freezeAgreement(agreementIds[index]);
    }
  }

  // external functions

  function claim(
    uint256[] calldata agreementIds
  ) external nonReentrant whenNotPaused {
    for (uint256 index = 0; index < agreementIds.length; ++index) {
      Agreement memory agreement = _validateClaim(agreementIds[index]);
      ERC20(agreement.asset).transferFixed(
        agreement.beneficiary,
        agreement.amount
      );
    }
  }

  // internal functions

  function _createAgreement(
    address asset,
    uint256 amount,
    address beneficiary,
    TimeLockDataTypes.AgreementContext agreementContext
  ) internal {
    _require(beneficiary != address(0), Errors.ZERO_ADDRESS);
    _require(amount > 0, Errors.INVALID_AMOUNT);

    uint48 releaseTime = uint48(block.timestamp) + releaseDelay;

    uint256 agreementId = agreementsByUser[beneficiary][agreementContext][
      asset
    ];
    if (agreementId == 0) {
      agreementId = ++agreementCount;
      Agreement memory agreement = Agreement({
        agreementContext: agreementContext,
        asset: asset,
        amount: amount,
        beneficiary: beneficiary,
        releaseTime: releaseTime,
        isFrozen: false
      });

      ERC20(asset).transferFromFixed(msg.sender, address(this), amount);

      agreementsByUser[beneficiary][agreementContext][asset] = agreementId;
      agreements[agreementId] = agreement;

      emit AgreementCreatedEvent(
        agreementId,
        beneficiary,
        agreementContext,
        asset,
        amount,
        releaseTime
      );
    } else {
      Agreement memory agreement = agreements[agreementId];
      agreement.amount += amount;
      agreement.releaseTime = releaseTime;

      ERC20(asset).transferFromFixed(msg.sender, address(this), amount);

      agreements[agreementId] = agreement;

      emit AgreementUpdatedEvent(
        agreementId,
        beneficiary,
        agreementContext,
        asset,
        agreement.amount,
        releaseTime
      );
    }
  }

  function _validateClaim(
    uint256 agreementId
  ) internal returns (Agreement memory) {
    Agreement memory agreement = agreements[agreementId];
    _require(
      msg.sender == agreement.beneficiary,
      Errors.BENEFICIARY_SENDER_MISMATCH
    );
    _require(
      block.timestamp >= agreement.releaseTime,
      Errors.RELEASE_TIME_NOT_REACHED
    );
    _require(!agreement.isFrozen, Errors.AGREEMENT_FROZEN);
    delete agreements[agreementId];
    delete agreementsByUser[agreement.beneficiary][agreement.agreementContext][
      agreement.asset
    ];

    emit AgreementClaimedEvent(
      agreementId,
      agreement.beneficiary,
      agreement.agreementContext,
      agreement.asset,
      agreement.amount,
      agreement.releaseTime
    );

    return agreement;
  }

  function _freezeAgreement(uint256 agreementId) internal {
    agreements[agreementId].isFrozen = true;
    emit AgreementFrozenEvent(agreementId, true);
  }
}

