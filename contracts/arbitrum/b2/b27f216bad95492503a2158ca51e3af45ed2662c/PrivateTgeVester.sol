// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./Initializable.sol";
import "./IPlutusPrivateTGE.sol";

contract PrivateTgeVester is Ownable, Pausable, Initializable {
  uint112 public constant ALLOCATION = 4_200_000 * 1e18;
  uint32 public constant CLIFF = 12 weeks;
  uint32 public constant VESTING_PERIOD = 12 weeks;
  uint112 public constant PRIVATE_TGE_TOTAL_RAISE = 284524761916000171659;

  IPlutusPrivateTGE public immutable privateTge;
  IERC20 public immutable pls;

  struct ClaimDetails {
    uint32 lastClaimedTimestamp;
    uint112 allocationLeft;
    uint112 claimedAmt;
  }

  uint32 public claimableAtTimestamp = 2**32 - 1;
  mapping(address => ClaimDetails) public claimDetails;

  constructor(
    IERC20 _pls,
    address _governance,
    address _privateTge
  ) {
    pls = _pls;
    privateTge = IPlutusPrivateTGE(_privateTge);
    _pause();
    transferOwnership(_governance);
  }

  function claimAllocation() external whenNotPaused {
    require(block.timestamp > claimableAtTimestamp, 'Cliff in effect');

    ClaimDetails storage _details = claimDetails[msg.sender];

    if (_details.lastClaimedTimestamp == 0) {
      // first time, calculate user allocation
      uint112 allocation = calculateShare(msg.sender, ALLOCATION);
      require(allocation > 0, 'No allocation');

      _details.lastClaimedTimestamp = claimableAtTimestamp;
      _details.allocationLeft = allocation;
    } else {
      require(block.timestamp > _details.lastClaimedTimestamp, 'Claim failed');
      require(_details.allocationLeft > 0, 'Fully claimed');
    }

    uint112 transferAmt;
    uint112 claimAmt = getClaimable(
      uint32(block.timestamp) - _details.lastClaimedTimestamp,
      calculateShare(msg.sender, ALLOCATION)
    );

    _details.lastClaimedTimestamp = uint32(block.timestamp);

    if (claimAmt > _details.allocationLeft) {
      transferAmt = _details.allocationLeft;
      _details.allocationLeft = 0;
    } else {
      transferAmt = claimAmt;
      _details.allocationLeft -= claimAmt;
    }

    _details.claimedAmt += transferAmt;
    pls.transfer(msg.sender, transferAmt);

    emit TokenClaim(msg.sender, transferAmt);
  }

  /** OWNER FUNCTIONS */
  function startVesting() external onlyOwner initializer {
    claimableAtTimestamp = uint32(block.timestamp) + CLIFF;
    _unpause();

    emit VestingStart(block.timestamp);
  }

  /// @dev retrieve stuck funds
  function retrieve(IERC20 _token) external onlyOwner {
    require(_token != pls, 'token = underlying');

    if (address(this).balance > 0) {
      payable(owner()).transfer(address(this).balance);
    }

    _token.transfer(owner(), _token.balanceOf(address(this)));
  }

  /** VIEWS */
  /// @dev Calculate a _user's share of _quantity
  function calculateShare(address _user, uint256 _quantity) public view returns (uint112) {
    return uint112((privateTge.deposit(_user) * _quantity) / PRIVATE_TGE_TOTAL_RAISE);
  }

  /** PURE */
  /// @dev Calculate claimable _shares based on vesting duration
  function getClaimable(uint32 _durationSinceLastClaim, uint112 _share) public pure returns (uint112) {
    return (_durationSinceLastClaim * _share) / VESTING_PERIOD;
  }

  event TokenClaim(address indexed recipient, uint256 amt);
  event VestingStart(uint256 timestamp);
}

