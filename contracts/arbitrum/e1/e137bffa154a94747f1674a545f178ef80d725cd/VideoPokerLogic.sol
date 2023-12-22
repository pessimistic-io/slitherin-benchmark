// SPDX-License-Identifier: MIT
pragma solidity >=0.4.15 <0.9.0;

contract VideoPokerLogic {
  uint private constant COUNT2 = 2 ** 16 - 1;
  uint private constant COUNT3 = 2 ** 32 - 1;
  uint private constant COUNT4 = 2 ** 48 - 1;

  uint private constant MASK_STRAIGHT_A = 4111; // 0b1000000001111
  uint private constant MASK_STRAIGHT_2 = 31; // 0b0000000011111
  uint private constant MASK_STRAIGHT_3 = 62; // 0b0000000111110
  uint private constant MASK_STRAIGHT_4 = 124; // 0b0000001111100
  uint private constant MASK_STRAIGHT_5 = 248; // 0b0000011111000
  uint private constant MASK_STRAIGHT_6 = 496; // 0b0000111110000
  uint private constant MASK_STRAIGHT_7 = 992; // 0b0001111100000
  uint private constant MASK_STRAIGHT_8 = 1984; // 0b0011111000000
  uint private constant MASK_STRAIGHT_9 = 3968; // 0b0111110000000
  uint private constant MASK_STRAIGHT_HIGH = 7936; // 0b1111100000000
  uint private constant MASK_JACKS_OR_BETTER = 503316480; // 0b1111000000000_0000000000000000

  uint private constant JACKS_OR_BETTER = 1;
  uint private constant TWO_PAIR = 2;
  uint private constant THREE_OF_A_KIND = 3;
  uint private constant STRAIGHT = 4;
  uint private constant FLUSH = 5;
  uint private constant FULL_HOUSE = 6;
  uint private constant FOUR_OF_A_KIND = 7;
  uint private constant STRAIGHT_FLUSH = 8;
  uint private constant ROYAL_FLUSH = 9;

  function win(uint cards) internal pure returns (uint) {
    // count cards
    // count is initialized using the first card without doing the `while` check
    uint count = 1 << (cards & 15);
    // other cards need to perform the offset check
    count |= offset(count, 1 << ((cards & 960) >> 6));
    count |= offset(count, 1 << ((cards & 61440) >> 12));
    count |= offset(count, 1 << ((cards & 3932160) >> 18));
    count |= offset(count, 1 << ((cards & 251658240) >> 24));
    if (count <= COUNT2) {
      // all cards have different values, no need to count unique values
      if (
        count == MASK_STRAIGHT_A ||
        count == MASK_STRAIGHT_2 ||
        count == MASK_STRAIGHT_3 ||
        count == MASK_STRAIGHT_4 ||
        count == MASK_STRAIGHT_5 ||
        count == MASK_STRAIGHT_6 ||
        count == MASK_STRAIGHT_7 ||
        count == MASK_STRAIGHT_8 ||
        count == MASK_STRAIGHT_9
      ) {
        if (isFlush(cards)) {
          return STRAIGHT_FLUSH;
        } else {
          return STRAIGHT;
        }
      } else if (count == MASK_STRAIGHT_HIGH) {
        // treat royal as a special case
        if (isFlush(cards)) {
          return ROYAL_FLUSH;
        } else {
          return STRAIGHT;
        }
      } else if (isFlush(cards)) {
        // can only be a flush if a.length is 5
        return FLUSH;
      }
    } else {
      // count how many different combinations of numbers there are
      // counting the number of 1s in the first 13 bits
      uint uniqueNumbers = countUniqueNumbers(count); // must be between 2 and 4
      if (uniqueNumbers == 2) {
        // there are only two unique numbers
        // must be whether a four of a kind or a full house
        if (count > COUNT4) {
          return FOUR_OF_A_KIND;
        } else {
          return FULL_HOUSE;
        }
      } else if (count > COUNT3) {
        // three of a kind
        return THREE_OF_A_KIND;
      } else if (uniqueNumbers == 3) {
        // two pair
        return TWO_PAIR;
      } else if ((count & MASK_JACKS_OR_BETTER) != 0) {
        // jacks or better
        return JACKS_OR_BETTER;
      }
    }
    return 0;
  }

  function offset(uint count, uint ioffset) private pure returns (uint) {
    while ((count & ioffset) != 0) {
      ioffset <<= 16;
    }
    return ioffset;
  }

  function countUniqueNumbers(uint count) private pure returns (uint) {
    uint ret = 0;
    if ((count & 1) != 0) ret++;
    if ((count & 2) != 0) ret++;
    if ((count & 4) != 0) ret++;
    if ((count & 8) != 0) ret++;
    if ((count & 16) != 0) ret++;
    if ((count & 32) != 0) ret++;
    if ((count & 64) != 0) ret++;
    if ((count & 128) != 0) ret++;
    if ((count & 256) != 0) ret++;
    if ((count & 512) != 0) ret++;
    if ((count & 1024) != 0) ret++;
    if ((count & 2048) != 0) ret++;
    if ((count & 4096) != 0) ret++;
    return ret;
  }

  /**
   * Indicates whether all the cards have the same suit.
   */
  function isFlush(uint cards) private pure returns (bool) {
    uint t = cards & 48; // 0b110000 (12 in decimal)
    return
      (cards & 3072) >> 6 == t && // 0b110000 shifted 6 bits to the right
      (cards & 196608) >> 12 == t && // 0b110000 shifted 12 bits to the right
      (cards & 12582912) >> 18 == t && // 0b110000 shifted 18 bits to the right
      (cards & 805306368) >> 24 == t; // 0b0110000 shifted 24 bits to the right
  }
}
