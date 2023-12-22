// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import { IJonesLpStaker, IPlsJonesRewardsDistro } from "./Interfaces.sol";
import "./console.sol";

contract PlsJonesRewardsDistro is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IPlsJonesRewardsDistro {
  uint private constant FEE_DIVISOR = 1e4;
  address public constant FEE_COLLECTOR = 0x9c140CD0F95D6675540F575B2e5Da46bFffeD31E;
  address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;
  address public constant GXP = 0x6fcce5033f33F4Aa3A55D9F6AD5D469254747679;
  address public constant CHEF = 0x72f45D0d088a5981075803A00846155ebf9e1097;
  IJonesLpStaker public constant STAKER = IJonesLpStaker(0x475e8a89aD4aF634663f2632Fff9E47e551f9600);

  mapping(address => bool) public isHandler;
  uint public pendingGxp;
  uint public pendingGrail;
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
    fee = 1500;
  }

  function handleClaimFees() external onlyHandler {
    (uint _gxpAmt, uint _grailAmt) = STAKER.claimFees(address(this));
    uint _fee = fee;

    console.log('gxpAmt', _gxpAmt);
    console.log('grailAmt', _grailAmt);

    if (_gxpAmt > 0) {
      unchecked {
        uint _plutusFee = ((_gxpAmt * _fee) / FEE_DIVISOR);
        IERC20(GXP).transfer(FEE_COLLECTOR, _plutusFee);

        uint rewardsLessFee = _gxpAmt - _plutusFee;
        pendingGxp += rewardsLessFee;
        console.log('pendingGxp', pendingGxp);
      }
    }

    if (_grailAmt > 0) {
      unchecked {
        uint _plutusFee = ((_grailAmt * _fee) / FEE_DIVISOR);
        IERC20(GRAIL).transfer(FEE_COLLECTOR, _plutusFee);

        uint rewardsLessFee = _grailAmt - _plutusFee;
        pendingGrail += rewardsLessFee;
        console.log('pendingGrail', pendingGrail);
      }
    }

    hasBufferedRewards = true;
  }

  /// @dev rewards in buffer, net of fees
  function pendingRewards() external view returns (uint _grailAmt, uint _gxpAmt) {
    _grailAmt = pendingGrail;
    _gxpAmt = pendingGxp;
  }

  /// @dev flush buffer and update chef state
  function record() external returns (uint _grailAmt, uint _gxpAmt) {
    if (msg.sender != CHEF) revert UNAUTHORIZED();

    _grailAmt = pendingGrail;
    _gxpAmt = pendingGxp;

    //flush buffer
    pendingGrail = 0;
    pendingGxp = 0;
    hasBufferedRewards = false;
  }

  /// @dev transfer rewards to user
  function sendRewards(address _to, uint _grailAmt, uint _gxpAmt) external {
    if (msg.sender != CHEF) revert UNAUTHORIZED();

    if (_grailAmt > 0) {
      _safeTokenTransfer(IERC20(GRAIL), _to, _grailAmt);
    }

    if (_gxpAmt > 0) {
      _safeTokenTransfer(IERC20(GXP), _to, _gxpAmt);
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

