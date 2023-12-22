// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./Initializable.sol";

contract TeamVester is Ownable {
  uint112 public constant ALLOCATION = 12_000_000 * 1e18;
  uint32 public constant CLIFF = 12 weeks;
  uint32 public constant VESTING_PERIOD = 12 weeks;

  IERC20 public immutable pls;

  struct ClaimDetails {
    uint32 lastClaimedTimestamp;
    uint112 allocationLeft;
    uint112 claimedAmt;
  }

  struct AllocationDetails {
    bool paused;
    uint32 claimableAtTimestamp;
    uint32 vestingPeriod;
    uint112 allocation;
  }

  mapping(address => ClaimDetails) public claimDetails;
  mapping(address => AllocationDetails) public allocationDetails;

  constructor(IERC20 _pls, address _governance) {
    pls = _pls;
    transferOwnership(_governance);
  }

  function claimAllocation() external {
    AllocationDetails memory allocDetails = allocationDetails[msg.sender];

    require(block.timestamp > allocDetails.claimableAtTimestamp, 'Cliff in effect');
    require(allocDetails.paused == false, 'Vesting paused');

    ClaimDetails storage _details = claimDetails[msg.sender];

    if (_details.lastClaimedTimestamp == 0) {
      // first time, calculate user allocation
      uint112 allocation = allocationDetails[msg.sender].allocation;
      require(allocation > 0, 'No allocation');

      _details.lastClaimedTimestamp = allocDetails.claimableAtTimestamp;
      _details.allocationLeft = allocation;
    } else {
      require(block.timestamp > _details.lastClaimedTimestamp, 'Claim failed');
      require(_details.allocationLeft > 0, 'Fully claimed');
    }

    uint112 transferAmt;
    uint112 claimAmt = getClaimable(
      msg.sender,
      uint32(block.timestamp) - _details.lastClaimedTimestamp,
      allocationDetails[msg.sender].allocation
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
  function addTeamMember(
    address _recipient,
    uint112 _alloc,
    uint32 _cliff,
    uint32 _vestingPeriod
  ) external onlyOwner {
    allocationDetails[_recipient] = AllocationDetails({
      allocation: _alloc,
      paused: false,
      claimableAtTimestamp: uint32(block.timestamp) + _cliff,
      vestingPeriod: _vestingPeriod
    });
  }

  function pauseVesting(address _recipient, bool _isPaused) external onlyOwner {
    allocationDetails[_recipient].paused = _isPaused;
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
  /// @dev Calculate claimable _shares based on vesting duration
  function getClaimable(
    address _recipient,
    uint32 _durationSinceLastClaim,
    uint112 _share
  ) public view returns (uint112) {
    return (_durationSinceLastClaim * _share) / allocationDetails[_recipient].vestingPeriod;
  }

  event TokenClaim(address indexed recipient, uint256 amt);
  event VestingStart(uint256 timestamp);
  event AddTeamMember(address indexed recipient, uint256 allocation, uint256 claimableAt, uint256 vestingDuration);
}

