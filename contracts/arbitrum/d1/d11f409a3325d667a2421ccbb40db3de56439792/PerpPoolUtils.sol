// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPoolCommitter,UserCommitment} from "./IPoolCommitter.sol";
import {ERC20} from "./ERC20.sol";
import {PriceUtils} from "./PriceUtils.sol";
import {PositionType} from "./PositionType.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract PerpPoolUtils is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  PriceUtils private priceUtils;

  function initialize(address _priceUtilsAddress) public initializer {
    priceUtils = PriceUtils(_priceUtilsAddress);

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function getCommittedUsdcWorth(address poolCommitterAddress, address perpPoolPositionManagerAddress) external view returns (uint256) {
    uint256 totalCommitments = 0;
    uint256 currentIndex = 0;
    IPoolCommitter poolCommitter = IPoolCommitter(poolCommitterAddress);

    while (true) {
      try poolCommitter.unAggregatedCommitments(perpPoolPositionManagerAddress,currentIndex) returns (uint256 intervalId) {
        UserCommitment memory userCommitment = poolCommitter.userCommitments(perpPoolPositionManagerAddress, intervalId);
        totalCommitments += userCommitment.shortMintSettlement;
        currentIndex += 1;
      } catch {
        break;
      }
    }

    return totalCommitments;
  }

  function getClaimedUsdcWorth(address poolToken, address owner, address leveragedPoolAddress) external view returns (uint256) {
    uint256 balance = ERC20(poolToken).balanceOf(owner);
    uint256 claimedAmount = balance * priceUtils.perpPoolTokenPrice(leveragedPoolAddress, PositionType.Short);
    return balance * claimedAmount;
  }

  function encodeCommitParams(
        uint256 amount,
        IPoolCommitter.CommitType commitType,
        bool fromAggregateBalance,
        bool payForClaim
    ) external pure returns (bytes32) {
        uint128 shortenedAmount = uint128(amount);
        bytes32 res;

        assembly {
            res := add(
                shortenedAmount,
                add(shl(128, commitType), add(shl(136, fromAggregateBalance), shl(144, payForClaim)))
            )
        }
        return res;
    }
}

