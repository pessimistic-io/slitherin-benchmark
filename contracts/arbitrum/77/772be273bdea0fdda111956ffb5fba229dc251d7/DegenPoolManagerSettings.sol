// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./IFeeCollector.sol";
import "./ITokenManager.sol";
import "./IReferralStorage.sol";
import "./ILuckyStrikeMaster.sol";
import "./IVault.sol";
import "./IDegenPoolManagerSettings.sol";
import "./ISwap.sol";

/**
 * @title DegenPoolManagerSettings
 * @author balding-ghost
 * @notice The DegenPoolManagerSettings contract is used to store all the settings for the DegenPoolManager contract.
 */
contract DegenPoolManagerSettings is IDegenPoolManagerSettings, AccessControl, Pausable {
  uint256 public constant BASIS_POINTS = 1e6; // 100%
  uint256 public constant SCALE = 1e8;
  uint256 public constant VAULT_SCALING_INCREASE_FOR_USD = 1e12;

  bytes32 public constant ADMIN_MAIN = bytes32(keccak256("ADMIN_MAIN"));
  bytes32 public constant ROUTER_ROLE = bytes32(keccak256("ROUTER_ROLE"));
  bytes32 public constant VAULT_ROLE = bytes32(keccak256("VAULT"));

  /// @notice Vault address
  IVault public immutable vault;
  bytes32 public immutable pythAssetId;
  IERC20 public immutable stableCoin;
  uint256 public immutable additionalPrecisionComparedToStableCoin;

  ISwap public swap;

  // @notice Fee settings

  // @note for auditor the python fee model we used had scaling for 1 usd of 1e8 and for percentages scaling of 1e8 as well. so the configs here reflect that.

  // @notice The maximum fee at the maximum position size, occurring at a 0.01% price move, is 82% of the profit.
  uint256 public constant maxFeeAtMaxPs = 82000000;
  // @notice The maximum fee at the minimum position size, occurring at a 0.01% price move, is 50% of the profit.
  uint256 public constant maxFeeAtMinPs = 50000000;
  // @notice The maximum position size in dollar value 1m$ * 1e8
  uint256 public constant maxPositionSize = 1000000 * SCALE;
  // @notice The minimum position size in dollar value 1$ * 1e8
  uint256 public constant minPositionSize = 1 * SCALE;
  // @notice The minimum fee percentage 10%
  uint256 public constant minFee = 10000000;
  // @notice The minimum price move percentage
  uint256 public constant minPriceMove = 10000;
  // @notice The maximum price move percentage 10%
  // @notice The pnl fee will be fixed after this price move
  // @notice The pnl fee will be 10% after this price move
  uint256 public constant maxPriceMove = 10000000;

  int256 public constant factor = int256(500001);

  address public degenGameContract;

  mapping(address => bool) public degenGameControllers;

  constructor(
    address _vault,
    address _swap,
    bytes32 _pythAssetId,
    address _admin,
    address _stableCoinAddress,
    uint256 _decimalsStableCoin
  ) {
    pythAssetId = _pythAssetId;
    vault = IVault(_vault);
    swap = ISwap(_swap);
    degenGameControllers[address(this)] = true;

    stableCoin = IERC20(_stableCoinAddress);
    additionalPrecisionComparedToStableCoin = 10 ** (18 - _decimalsStableCoin);

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(ADMIN_MAIN, _admin);
  }

  modifier onlyAdmin() {
    require(hasRole(ADMIN_MAIN, msg.sender), "DegenPoolManager: only admin main");
    _;
  }

  modifier onlyRouter() {
    require(hasRole(ROUTER_ROLE, msg.sender), "DegenPoolManager: only router");
    _;
  }

  modifier onlyDegenGame() {
    require(msg.sender == degenGameContract, "DegenPoolManager: only degen game");
    _;
  }

  // Contract configuration

  function setSwap(address _swap) external onlyAdmin {
    swap = ISwap(_swap);
  }

  function setDegenGameContract(address _degenGameContract) external onlyAdmin {
    require(degenGameContract == address(0), "DegenPoolManager: already set");
    degenGameContract = _degenGameContract;
    emit DegenGameContractSet(_degenGameContract);
  }

  function addRouter(address _router, bool _setting) external onlyAdmin {
    if (_setting) {
      grantRole(ROUTER_ROLE, _router);
    } else {
      revokeRole(ROUTER_ROLE, _router);
    }
  }

  function setDegenGameController(
    address _degenGameController,
    bool _isDegenGameController
  ) external onlyAdmin {
    degenGameControllers[_degenGameController] = _isDegenGameController;
    emit DegenGameControllerSet(_degenGameController, _isDegenGameController);
  }

  function isDegenGameController(
    address _degenGameController
  ) external view returns (bool isController_) {
    isController_ = degenGameControllers[_degenGameController];
  }
}

