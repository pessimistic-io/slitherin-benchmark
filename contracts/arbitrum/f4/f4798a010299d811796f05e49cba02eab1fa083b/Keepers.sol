// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { IMinter } from "./IMinter.sol";
import { IVoter2 } from "./IVoter2.sol";
import { IEpochFlipper } from "./IEpochFlipper.sol";

contract Keepers {
   uint constant WEEK = 7 days;
   uint private period;
   IMinter private immutable _minter;
   IVoter2 private immutable _voter;
   IEpochFlipper private immutable _epochFlipper;
   address private immutable _xcal;
   address private admin;
   bool public boostedVeDistSuccess;
   bool public boostedGaugeDistSuccess;
   bool public distributeSuccess;
   bool public distributeFeesSuccess;

   event Log(uint);

   constructor(address minter, address voter, address xcal, address epochFlipper) {
      _minter = IMinter(minter);
      _voter = IVoter2(voter);
      _epochFlipper = IEpochFlipper(epochFlipper);
      _xcal = xcal;
      // last thursday 12PM UTC
      period = (block.timestamp / WEEK) * WEEK;
   }

   function checkUpkeep() external view returns (bool upkeepNeeded, bytes memory performData) {
      upkeepNeeded = block.timestamp > (period + WEEK);
      performData = abi.encode(getPerformData());
   }

   function performUpkeep(bytes memory performData) external {
      if (block.timestamp > (period + WEEK)) {
         // decode calldata
         address[] memory _gauges = abi.decode(performData, (address[]));

         try _epochFlipper.veDistBoost() {
            boostedVeDistSuccess = true;
         } catch {
            boostedVeDistSuccess = false;
         }

         _minter.update_period();

         try _voter.distribute() {
            distributeSuccess = true;
         } catch {
            distributeSuccess = false;
         }

         try _voter.distributeFees(_gauges) {
            distributeFeesSuccess = true;
         } catch {
            distributeFeesSuccess = false;
         }

         try _epochFlipper.boostSelectedGauges() {
            boostedGaugeDistSuccess = true;
         } catch {
            boostedGaugeDistSuccess = false;
         }

         period += WEEK;
      }
   }

   function getPerformData() public view returns (address[] memory) {
      // number of gauges registered on voter
      uint _length = _voter.length();
      // all gauges registered on voter
      address[] memory _gauges = gauges(_length);
      // gauges with non-zero rewards
      (address[] memory _validGauges, uint _count) = validGauges(_gauges, _length);

      return trim(_validGauges, _count);
   }

   function gauges(uint length) public view returns (address[] memory) {
      address[] memory _gauges = new address[](length);
      for (uint i; i < length; i++) {
         _gauges[i] = _voter.allGauges(i);
      }
      return _gauges;
   }

   function validGauges(address[] memory allGauges, uint length) public view returns (address[] memory, uint) {
      address[] memory _validGauges = new address[](length);
      uint _c;
      for (uint i; i < length; i++) {
         if (_voter.weights(allGauges[i]) != 0) {
            _validGauges[_c] = allGauges[i];
            _c++;
         }
      }
      return (_validGauges, _c);
   }

   function trim(address[] memory arr, uint count) internal pure returns (address[] memory) {
      address[] memory _trimmed = new address[](count);
      for (uint i; i < count; i++) {
         _trimmed[i] = arr[i];
      }
      return _trimmed;
   }
}

