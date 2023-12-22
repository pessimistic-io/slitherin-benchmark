// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import { IPrivateTgeHelper } from "./PrivateTgeHelper.sol";

contract PrivateTgeVester is Ownable, Pausable {
  IERC20 private constant PLS = IERC20(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
  IPrivateTgeHelper private constant TGE_HELPER = IPrivateTgeHelper(0xEC06E18b64b54470Eb423A245640600155aD3427);

  struct ClaimDetails {
    uint32 lastClaimedTimestamp;
    uint112 allocationLeft;
    uint112 claimedAmt;
  }

  mapping(address => ClaimDetails) public claimDetails;

  function claimAllocation() external whenNotPaused {
    require(block.timestamp > TGE_HELPER.claimStartAt(), 'Cliff in effect');

    ClaimDetails storage _details = claimDetails[msg.sender];

    if (_details.lastClaimedTimestamp == 0) {
      // first time, calculate user allocation
      uint112 allocation = uint112(TGE_HELPER.plsClaimable(msg.sender));
      require(allocation > 0, 'No allocation');

      _details.lastClaimedTimestamp = uint32(TGE_HELPER.claimStartAt());
      _details.allocationLeft = allocation;
    } else {
      require(block.timestamp > _details.lastClaimedTimestamp, 'Claim failed');
      require(_details.allocationLeft > 0, 'Fully claimed');
    }

    uint112 transferAmt;
    uint112 claimAmt = getClaimable(
      uint32(block.timestamp) - _details.lastClaimedTimestamp,
      uint112(TGE_HELPER.plsClaimable(msg.sender))
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
    _safeTokenTransfer(PLS, msg.sender, transferAmt);

    emit TokenClaim(msg.sender, transferAmt);
  }

  function _safeTokenTransfer(
    IERC20 _token,
    address _to,
    uint256 _amount
  ) private {
    uint256 bal = _token.balanceOf(address(this));

    if (_amount > bal) {
      _token.transfer(_to, bal);
    } else {
      _token.transfer(_to, _amount);
    }
  }

  /** OWNER FUNCTIONS */
  /// @dev retrieve stuck funds
  function retrieve(IERC20 _token) external onlyOwner {
    require(_token != PLS, 'token = underlying');

    if (address(this).balance > 0) {
      payable(owner()).transfer(address(this).balance);
    }

    _token.transfer(owner(), _token.balanceOf(address(this)));
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  /** VIEW */
  /// @dev Calculate claimable _shares based on vesting duration
  function getClaimable(uint32 _durationSinceLastClaim, uint112 _share) public view returns (uint112) {
    return uint112((_durationSinceLastClaim * _share) / TGE_HELPER.VESTING_PERIOD());
  }

  /// @dev For frontend
  function pendingClaims(address _user)
    external
    view
    returns (
      uint256 _claimable,
      uint256 _claimed,
      uint256 _allocation
    )
  {
    ClaimDetails memory _details = claimDetails[_user];
    _allocation = TGE_HELPER.plsClaimable(_user);

    if (_details.lastClaimedTimestamp == 0) {
      if (block.timestamp < TGE_HELPER.claimStartAt()) {
        _claimable = 0;
      } else {
        _claimable = getClaimable(
          uint32(block.timestamp - TGE_HELPER.claimStartAt()),
          uint112(TGE_HELPER.plsClaimable(_user))
        );
      }
      _claimed = 0;
    } else {
      _claimable = getClaimable(
        uint32(block.timestamp) - _details.lastClaimedTimestamp,
        uint112(TGE_HELPER.plsClaimable(_user))
      );

      _claimed = _details.claimedAmt;
    }
  }

  event TokenClaim(address indexed recipient, uint256 amt);
}

