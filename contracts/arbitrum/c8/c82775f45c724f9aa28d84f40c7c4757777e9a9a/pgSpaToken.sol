// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./Ownable.sol";

interface IEscrow {
  function balanceOf(address addr) external view returns (uint256);
}

contract PgSpaToken is ERC20, Ownable {
  IEscrow public constant VE_SPA = IEscrow(0x2e2071180682Ce6C247B1eF93d382D509F5F6A17);
  uint256 public constant TOTAL_ALLOC_POINTS = 10000;
  address public constant SPA_STAKER = 0x46ac70bf830896EEB2a2e4CBe29cD05628824928;

  uint256 public cumulativeAllocPoints;
  mapping(address => uint256) public delegates;

  constructor() ERC20('Plutus Governance SPA', 'pgSPA') {}

  /**
   * Return veSPA balance of Plutus
   */
  function totalSupply() public view override returns (uint256) {
    return VE_SPA.balanceOf(SPA_STAKER);
  }

  /**
   * Return veSPA balance of Plutus prorated by delegate
   */
  function balanceOf(address account) public view override returns (uint256) {
    if (delegates[account] != 0) {
      return (delegates[account] * totalSupply()) / TOTAL_ALLOC_POINTS;
    } else {
      return 0;
    }
  }

  function _isContract(address _addr) private view returns (bool isContract) {
    uint32 size;
    assembly {
      size := extcodesize(_addr)
    }
    return (size > 0);
  }

  /** OWNER FUNCTIONS */

  ///@notice delegate must be an EOA, used for snapshot voting
  function updateDelegate(address _delegate, uint256 _allocPoints) external onlyOwner {
    if (_delegate == address(0) || _isContract(_delegate)) revert BAD_DELEGATE();
    uint256 oldAllocPoints = delegates[_delegate];
    cumulativeAllocPoints -= oldAllocPoints;

    delegates[_delegate] = _allocPoints;
    cumulativeAllocPoints += _allocPoints;

    if (cumulativeAllocPoints > TOTAL_ALLOC_POINTS) revert ALLOC_EXCEEDED();
  }

  event DelegateUpdated(address indexed _delegate, uint256 _allocPoints);

  error UNAUTHORIZED();
  error ALLOC_EXCEEDED();
  error BAD_DELEGATE();
}

