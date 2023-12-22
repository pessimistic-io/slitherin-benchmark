// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IVoter.sol";
import "./IMinter.sol";
import "./IGauge.sol";
import "./IVotingEscrow.sol";
import "./IVotingDist.sol";
import "./IERC20.sol";

struct NextEpochData {
   uint256 boostedDistAmount;
   address[] gauges;
   uint256[] boostedAmounts;
}

contract EpochFlipper {
   uint internal constant DURATION = 7 days;
   uint256 internal constant MAX_INT = 2 ** 256 - 1;

   IVoter private immutable voter;
   address private immutable votingDist;
   address private base; //XCAL token address

   //only 2 addresses that can interact w/ this contract
   address public owner;
   address public keeper;

   //Boosted emissions are distributed based on this struct
   NextEpochData internal nextEpochBoostedData;

   constructor(address _voter, address _votingDist, address _tokenAddress, address _owner) {
      voter = IVoter(_voter);
      votingDist = _votingDist;
      base = _tokenAddress;
      owner = _owner;
      nextEpochBoostedData = NextEpochData(0, new address[](0), new uint256[](0));
   }

   modifier onlyOwner() {
      require(msg.sender == owner, "only owner");
      _;
   }

   modifier onlyOwnerOrKeeper() {
      require(msg.sender == owner || msg.sender == keeper, "only owner or keeper");
      _;
   }

   //would require sending _nextEpochBoostedAmount to the contract before next epoch flip, else calling boostSelectedGauges() && veDistBoost() would fail
   function updateNextEpochData(
      uint256 _nextEpochBoostedDistAmount,
      address[] calldata _gauges,
      uint256[] calldata _amounts
   ) public onlyOwner {
      nextEpochBoostedData.boostedDistAmount = _nextEpochBoostedDistAmount;
      nextEpochBoostedData.gauges = _gauges;
      nextEpochBoostedData.boostedAmounts = _amounts;
   }

   function getNextEpochData() public view returns (NextEpochData memory) {
      return nextEpochBoostedData;
   }

   function updateKeeper(address _keeper) public onlyOwner {
      keeper = _keeper;
   }

   function updateOwner(address _owner) public onlyOwner {
      owner = _owner;
   }

   //should be called before minter.update_period()
   function veDistBoost() public onlyOwnerOrKeeper {
      require(nextEpochBoostedData.boostedDistAmount > 0);
      _safeTransfer(base, votingDist, nextEpochBoostedData.boostedDistAmount);
      nextEpochBoostedData = NextEpochData(0, nextEpochBoostedData.gauges, nextEpochBoostedData.boostedAmounts);
   }

   //should be called after minter.update_period() and voter.distro()
   function boostSelectedGauges() public onlyOwnerOrKeeper {
      _updateGaugeEmissions(nextEpochBoostedData.gauges, nextEpochBoostedData.boostedAmounts);
      nextEpochBoostedData = NextEpochData(nextEpochBoostedData.boostedDistAmount, new address[](0), new uint256[](0));
   }

   function withdrawAll() public onlyOwner {
      withdrawAmount(IERC20(base).balanceOf(address(this)));
   }

   function withdrawAmount(uint256 amount) public onlyOwner {
      _safeTransfer(base, owner, amount);
   }

   function _updateGaugeEmissions(address[] memory gauges, uint256[] memory boostedAmounts) internal {
      require(nextEpochBoostedData.gauges.length > 0, "Must have atleast 1 gauge");
      require(gauges.length == boostedAmounts.length, "Array lengths must be equal");
      for (uint256 index = 0; index < gauges.length; index++) {
         require(
            voter.isLive(gauges[index]) && voter.weights(gauges[index]) > 0,
            "Cannot boost emissions for dead gauges"
         );
         uint256 _claimable = boostedAmounts[index];
         require(
            _claimable > 0 && _claimable > IGauge(gauges[index]).left(base) && _claimable / DURATION > 0,
            "Boosted emissions must be greater than base gauge emissions"
         );
         IERC20(base).approve(gauges[index], MAX_INT);
         IGauge(gauges[index]).notifyRewardAmount(base, _claimable);
      }
   }

   function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
      require(token.code.length > 0);
      (bool success, bytes memory data) = token.call(
         abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
      );
      require(success && (data.length == 0 || abi.decode(data, (bool))));
   }

   function _safeTransfer(address token, address to, uint256 value) internal {
      require(token.code.length > 0);
      (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
      require(success && (data.length == 0 || abi.decode(data, (bool))));
   }
}

