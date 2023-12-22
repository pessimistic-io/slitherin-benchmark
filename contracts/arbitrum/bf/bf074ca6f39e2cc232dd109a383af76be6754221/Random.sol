// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IArbSys.sol";

//=========================================================================================================================================
// We're trying to normalize all chances close to 100%, which is 100 000 with decimal point 10^3. Assuming this, we can get more "random"
// numbers by dividing the "random" number by this prime. To be honest most primes larger than 100% should work, but to be safe we'll
// use an order of magnitude higher (10^3) relative to the decimal point
// We're using uint256 (2^256 ~= 10^77), which means we're safe to derive 8 consecutive random numbers from each hash.
// If we, by any chance, run out of random numbers (hash being lower than the range) we can in turn
// use the remainder of the hash to regenerate a new random number.
// Example: assuming our hash function result would be 1132134687911000 (shorter number picked for explanation) and we're using
// % 100000 range for our drop chance. The first "random" number is 11000. We then divide 1000000011000 by the 100000037 prime,
// leaving us at 11321342. The second derived random number would be 11321342 % 100000 = 21342. 11321342/100000037 is in turn less than
// 100000037, so we'll instead regenerate a new hash using 11321342.
// Primes are used for additional safety, but we could just deal with the "range".
//=========================================================================================================================================
uint256 constant MIN_SAFE_NEXT_NUMBER_PRIME = 1000033;
uint256 constant HIGH_RANGE_PRIME_OFFSET = 13;

library Random {
  function startRandomBase(
    uint256 _highSalt,
    uint256 _lowSalt
  ) internal view returns (uint256) {
    return
      uint256(
        keccak256(
          abi.encodePacked(
            ArbSys(address(0x64)).arbBlockHash(
              ArbSys(address(0x64)).arbBlockNumber() - 1
            ),
            msg.sender,
            _lowSalt,
            _highSalt
          )
        )
      );
  }

  function getNextRandom(
    uint256 randomBase,
    uint256 range
  ) internal view returns (uint256 random, uint256 nextBase) {
    uint256 nextNumberSeparator = MIN_SAFE_NEXT_NUMBER_PRIME > range
      ? MIN_SAFE_NEXT_NUMBER_PRIME
      : (range + HIGH_RANGE_PRIME_OFFSET);
    uint256 nextBaseNumber = randomBase / nextNumberSeparator;
    if (nextBaseNumber > nextNumberSeparator) {
      return (randomBase % range, nextBaseNumber);
    }
    nextBaseNumber = uint256(
      keccak256(
        abi.encodePacked(
          ArbSys(address(0x64)).arbBlockHash(
            ArbSys(address(0x64)).arbBlockNumber() - 1
          ),
          msg.sender,
          randomBase,
          range
        )
      )
    );
    return (nextBaseNumber % range, nextBaseNumber / nextNumberSeparator);
  }
}

