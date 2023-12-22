// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import { IPlsRdntPlutusChef, IPlsRdntRewardsDistroV2, IRdntLpStaker, IAToken } from "./Interfaces.sol";
import { IProtocolRewardsHandler } from "./Radiant.sol";

contract PlsRdntRewardsDistroV2 is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IPlsRdntRewardsDistroV2 {
  address public constant CHEF = 0xaE3f67589Acb90bd2cbccD8285b37fe4F8F29042;
  uint private constant FEE_DIVISOR = 1e4;
  IRdntLpStaker public constant STAKER = IRdntLpStaker(0x2A2CAFbB239af9159AEecC34AC25521DBd8B5197);
  address public constant FEE_COLLECTOR = 0x9c140CD0F95D6675540F575B2e5Da46bFffeD31E;

  mapping(address => bool) public isHandler;
  mapping(address => uint) public rewardsBuffer; // underlyingToken -> amount
  uint32 public fee; // fee in bp
  bool public hasBufferedRewards;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    isHandler[msg.sender] = true;
    fee = 1200;
  }

  function handleClaimAndUnwrap() external onlyHandler {
    IProtocolRewardsHandler.RewardData[] memory _rewardsData = STAKER.claimRadiantProtocolFees(address(this)); // tokens in underlying asset

    uint _fee = fee;
    for (uint i; i < _rewardsData.length; i = _unsafeInc(i)) {
      uint _amount = _rewardsData[i].amount;

      if (_amount > 0) {
        unchecked {
          uint _plutusFee = ((_amount * _fee) / FEE_DIVISOR);
          IERC20(_rewardsData[i].token).transfer(FEE_COLLECTOR, _plutusFee);
          // adjusted to account for fees
          _rewardsData[i].amount = _amount - _plutusFee;

          // write pending to rewards buffer
          rewardsBuffer[_rewardsData[i].token] += _rewardsData[i].amount;
        }
      }
    }

    hasBufferedRewards = true;
    emit HandleClaim(_rewardsData);
  }

  function handleClaim() external onlyHandler {
    STAKER.claimProtocolFees();
  }

  function handleUnwrap(address[] memory _tokens) external onlyHandler {
    IProtocolRewardsHandler.RewardData[] memory _rewardsData = STAKER.unwrapATokens(address(this), _tokens); // tokens in underlying asset

    uint _fee = fee;
    for (uint i; i < _rewardsData.length; i = _unsafeInc(i)) {
      uint _amount = _rewardsData[i].amount;

      if (_amount > 0) {
        unchecked {
          uint _plutusFee = ((_amount * _fee) / FEE_DIVISOR);
          IERC20(_rewardsData[i].token).transfer(FEE_COLLECTOR, _plutusFee);
          // adjusted to account for fees
          _rewardsData[i].amount = _amount - _plutusFee;

          // write pending to rewards buffer
          rewardsBuffer[_rewardsData[i].token] += _rewardsData[i].amount;
        }
      }
    }

    hasBufferedRewards = true;
    emit HandleClaim(_rewardsData);
  }

  /// @dev rewards in buffer, net of fees
  function pendingRewards() external view returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewards) {
    address[] memory _rewardTokens = STAKER.getRewardTokens();
    _pendingRewards = new IProtocolRewardsHandler.RewardData[](_rewardTokens.length);

    for (uint i; i < _rewardTokens.length; i = _unsafeInc(i)) {
      address underlyingToken = IAToken(_rewardTokens[i]).UNDERLYING_ASSET_ADDRESS();
      _pendingRewards[i] = IProtocolRewardsHandler.RewardData({
        token: underlyingToken,
        amount: rewardsBuffer[underlyingToken]
      });
    }
  }

  /// @dev flush buffer and update chef state
  function record() external returns (IProtocolRewardsHandler.RewardData[] memory _pendingRewards) {
    if (msg.sender != CHEF) revert UNAUTHORIZED();
    address[] memory _rewardTokens = STAKER.getRewardTokens();
    _pendingRewards = new IProtocolRewardsHandler.RewardData[](_rewardTokens.length);

    for (uint i; i < _rewardTokens.length; i = _unsafeInc(i)) {
      address underlyingToken = IAToken(_rewardTokens[i]).UNDERLYING_ASSET_ADDRESS();
      _pendingRewards[i] = IProtocolRewardsHandler.RewardData({
        token: underlyingToken,
        amount: rewardsBuffer[underlyingToken]
      });

      // flush buffer
      rewardsBuffer[underlyingToken] = 0;
    }

    hasBufferedRewards = false;
  }

  /// @dev transfer rewards to user
  function sendRewards(address _to, IProtocolRewardsHandler.RewardData[] memory _pendingRewardAmounts) external {
    if (msg.sender != CHEF) revert UNAUTHORIZED();
    uint _len = _pendingRewardAmounts.length;

    for (uint i; i < _len; i = _unsafeInc(i)) {
      address _rewardToken = _pendingRewardAmounts[i].token;
      uint _amount = _pendingRewardAmounts[i].amount;

      if (_amount > 0) {
        _safeTokenTransfer(IERC20(_rewardToken), _to, _amount);
      }
    }
  }

  function _unsafeInc(uint x) private pure returns (uint) {
    unchecked {
      return x + 1;
    }
  }

  function _safeTokenTransfer(IERC20 _token, address _to, uint256 _amount) private {
    uint256 bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  modifier onlyHandler() {
    if (isHandler[msg.sender] == false) revert UNAUTHORIZED();
    _;
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function setFee(uint32 _fee) external onlyOwner {
    if (_fee > FEE_DIVISOR) {
      revert INVALID_FEE();
    }

    emit FeeChanged(_fee, fee);
    fee = _fee;
  }

  function updateHandler(address _handler, bool _isActive) public onlyOwner {
    isHandler[_handler] = _isActive;
  }
}

