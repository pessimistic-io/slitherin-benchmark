// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import { SafeERC20Upgradeable as SafeERC20 } from "./SafeERC20Upgradeable.sol";
import { ERC165CheckerUpgradeable as ERC165Checker } from "./ERC165CheckerUpgradeable.sol";

import { ECDSAUpgradeable as ECDSA } from "./ECDSAUpgradeable.sol";

// Using a draft contract isn't great, as is using EIP712 which is technically still under "Review"
// EIP712 was created over 4 years ago and has undegone multiple versions since
// Metamask supports multiple various versions of EIP712 and is committed to maintaing "v3" and "v4" support
// The only distinction between the two is the support for arrays/structs in structs, which aren't used by these contracts
// Therefore, this usage is fine, now and in the long-term, as long as one of those two versions is indefinitely supported
import "./draft-EIP712Upgradeable.sol";

import { IERC20MetadataUpgradeable as IERC20Metadata } from "./IERC20MetadataUpgradeable.sol";

import "./IIntegratedLimitOrderDEX.sol";
import "./IAuction.sol";
import "./IFrabricBeacon.sol";

import "./DAO.sol";

import "./IFrabricDAO.sol";

/**
 * @title FrabricDAO Contract
 * @author Fractional Finance
 *
 * @dev Implements proposals mutual to both Threads and the Frabric
 * This could be merged directly into DAO, as the Thread and Frabric contracts use this,
 * yet DAO is only used by this
 * This offers smaller, more compartamentalized code, and directly integrating the two
 * doesn't actually offer any efficiency benefits. The new structs, the new variables, and
 * the new code are still needed, meaning it really just inlines _completeProposal
 */
abstract contract FrabricDAO is EIP712Upgradeable, DAO, IFrabricDAO {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  /// @notice Bit value indicating a proposal is a common proposal
  uint16 constant public override commonProposalBit = 1 << 8;

  /// @notice Maximum percentage fee to enforce upon removal of a participant
  uint8 public override maxRemovalFee;

  struct Upgrade {
    address beacon;
    address instance;
    address code;
    uint256 version;
    bytes data;
  }
  mapping(uint256 => Upgrade) private _upgrades;

  struct TokenAction {
    address token;
    address target;
    bool mint;
    uint256 price;
    uint256 amount;
  }
  mapping(uint256 => TokenAction) private _tokenActions;

  struct Removal {
    address participant;
    uint8 fee;
  }
  mapping(uint256 => Removal) private _removals;

  uint256[100] private __gap;

  function __FrabricDAO_init(
    string memory name,
    address _erc20,
    uint64 _votingPeriod,
    uint8 _maxRemovalFee
  ) internal onlyInitializing {
    // This unfortunately doesn't use the Composable version, yet unless we change
    // the signing structs, we shouldn't need to upgrade this (even if EIP 712 would like us to)
    __EIP712_init(name, "1");
    __DAO_init(_erc20, _votingPeriod);
    supportsInterface[type(IFrabricDAO).interfaceId] = true;

    // Ensure this is a valid percentage
    if (_maxRemovalFee > 100) {
      revert InvalidRemovalFee(_maxRemovalFee, 100);
    }
    maxRemovalFee = _maxRemovalFee;
  }

  function _isCommonProposal(uint16 pType) internal pure returns (bool) {
    // Uses a shift instead of a bit mask to ensure this is the only bit set
    return (pType >> 8) == 1;
  }

  /**
   * @notice Create a new paper proposal (a statement agreed upon by the DAO without technical action)
   * @param supermajority true if a supermajority is required for the proposal to pass
   * @param info Statement to be put to a vote
   * @return uint256 ID of the created proposal
   */
  function proposePaper(bool supermajority, bytes32 info) external override returns (uint256) {
    // No dedicated event as the DAO emits type and info
    return _createProposal(uint16(CommonProposalType.Paper) | commonProposalBit, supermajority, info);
  }

  /**
   * @notice Propose a contract upgrade for this contract or one owned by it
   * @param beacon Address of the beacon contract facilitating upgrades
   * @param instance Address of the contract instance to be upgraded
   * @param version Version number of the new contract
   * @param code Address of the contract with the new code
   * @param data Data to be passed to new contract when triggering the upgrade
   * @param info Additional information about proposal
   * @return id ID of created proposal
   * @dev Specifying any irrelevant beacon will work yet won't have any impact
   * Specifying an arbitrary contract would also work if it has functions/
   * a fallback function which doesn't error when called
   * Between human review, function definition requirements, and the lack of privileges bestowed,
   * this is considered to be appropriately managed
   */
  function proposeUpgrade(
    address beacon,
    address instance,
    uint256 version,
    address code,
    bytes calldata data,
    bytes32 info
  ) public virtual override returns (uint256 id) {
    if (!beacon.supportsInterface(type(IFrabricBeacon).interfaceId)) {
      revert UnsupportedInterface(beacon, type(IFrabricBeacon).interfaceId);
    }
    bytes32 beaconName = IFrabricBeacon(beacon).beaconName();

    if (!code.supportsInterface(type(IComposable).interfaceId)) {
      revert UnsupportedInterface(code, type(IComposable).interfaceId);
    }
    bytes32 codeName = IComposable(code).contractName();

    // This check is also performed by the Beacon itself when calling upgrade
    // It's just optimal to prevent this proposal from ever existing and being pending if it's not valid
    // Since this doesn't check instance's contractName, it could be setting an implementation of X
    // on beacon X, yet this is pointless. Because the instance is X, its actual beacon must be X,
    // and it will never accept this implementation (which isn't even being passed to it)
    if (beaconName != codeName) {
      revert DifferentContract(beaconName, codeName);
    }

    id = _createProposal(uint16(CommonProposalType.Upgrade) | commonProposalBit, true, info);
    _upgrades[id] = Upgrade(beacon, instance, code, version, data);
    // Doesn't index code as parsing the Beacon's logs for its indexed code argument
    // will return every time a contract upgraded to it
    // This combination of options should be competent for almost all use cases
    // The only missing indexing case is when it's proposed to upgrade, yet that never passes/executes
    // This should be minimally considerable and coverable by outside solutions if truly needed
    emit UpgradeProposal(id, beacon, instance, version, code, data);
  }

  /**
   * @notice Create a proposal to mint, transfer, sell, auction tokens, or cancel a standing sell order.
   * Combined actions are supported
   * @param token Address of the token to act on
   * @param target Target address for the action. Either the recipient, this contract if selling on the DEX,
   * or the auction contract if selling at auction
   * @param price Price of tokens to create/cancel a DEX sell order at
   * @param amount Quantity of tokens to act with. 0 if cancelling an order
   * @param info Information on this proposal
   * @return id Id of created proposal
   */
  function proposeTokenAction(
    address token,
    address target,
    bool mint,
    uint256 price,
    uint256 amount,
    bytes32 info
  ) external override returns (uint256 id) {
    bool supermajority = false;

    if (mint) {
      // All of this mint code should work and will be reviewed by auditors to confirm that
      // That said, at this time, we are not launching with any form of minting enabled
      // Solely commented during development to enable running tests on this code
      // revert Minting();

      supermajority = true;
      if (token != erc20) {
        revert MintingDifferentToken(token, erc20);
      }
    }

    if (price != 0) {
      // Target is ignored when selling tokens, yet not when minting them
      // This enables minting and directly selling tokens, and removes mutability reducing scope
      if (target != address(this)) {
        revert TargetMalleability(target, address(this));
      }

      // Ensure that we know how to sell this token
      if (!token.supportsInterface(type(IIntegratedLimitOrderDEXCore).interfaceId)) {
        revert UnsupportedInterface(token, type(IIntegratedLimitOrderDEXCore).interfaceId);
      }

      // Because this is an ILO DEX, amount here will be atomic yet the ILO DEX
      // will expect it to be whole
      uint256 whole = 10 ** IERC20Metadata(token).decimals();
      if ((amount / whole * whole) != amount) {
        revert NotRoundAmount(amount);
      }
    // Only allow a zero amount to cancel an order at a given price
    } else if (amount == 0) {
      revert ZeroAmount();
    }

    id = _createProposal(uint16(CommonProposalType.TokenAction) | commonProposalBit, supermajority, info);
    _tokenActions[id] = TokenAction(token, target, mint, price, amount);
    emit TokenActionProposal(id, token, target, mint, price, amount);
  }

  /**
   * @notice Propose removal of `participant`
   * @param participant Address of participant proposed for removal
   * @param removalFee Percentage fee to charge `participant` on removal, intended to recover financial damage
   * @param signatures Array of signatures from users voting on this proposal in advance, in order to freeze the
   * funds of the participant for the duration of this proposal
   * @param info Any extra information about the proposal
   * @return id ID of created proposal
   */
  function proposeParticipantRemoval(
    address participant,
    uint8 removalFee,
    bytes[] calldata signatures,
    bytes32 info
  ) public virtual override returns (uint256 id) {
    if (participant == address(this)) {
      revert Irremovable(participant);
    }

    if (removalFee > maxRemovalFee) {
      revert InvalidRemovalFee(removalFee, maxRemovalFee);
    }

    id =  _createProposal(uint16(CommonProposalType.ParticipantRemoval) | commonProposalBit, false, info);
    _removals[id] = Removal(participant, removalFee);
    emit ParticipantRemovalProposal(id, participant, removalFee);

    // If signatures were provided, then the purpose is to freeze this participant's
    // funds for the duration of the proposal. This will not affect any existing
    // DEX orders yet will prevent further DEX orders from being placed. This prevents
    // dumping (which already isn't incentivized as tokens will be put up for auction)
    // and games of hot potato where they're transferred to friends/associates to
    // prevent their re-distribution. While they can also buy their own tokens off
    // the Auction contract (with an alt), this is a step closer to being an optimal
    // system

    // If this is done maliciously, whoever proposed this should be removed themselves
    if (signatures.length != 0) {
      if (!erc20.supportsInterface(type(IFreeze).interfaceId)) {
        revert UnsupportedInterface(erc20, type(IFreeze).interfaceId);
      }

      // Create a nonce out of freezeUntil, as this will solely increase
      uint256 freezeUntilNonce = IFreeze(erc20).frozenUntil(participant) + 1;
      for (uint256 i = 0; i < signatures.length; i++) {
        // Vote with the recovered signer. This will tell us how many votes they
        // have in the end, and if these people are voting to freeze their funds,
        // they believe they should be removed. They can change their mind later

        // Safe usage as this proposal is guaranteed to be active
        // If this account had already voted, _voteUnsafe will remove their votes
        // before voting again, making this safe against repeat signers
        _voteUnsafe(
          id,
          ECDSA.recover(
            _hashTypedDataV4(
              keccak256(
                abi.encode(
                  keccak256("Removal(address participant,uint8 removalFee,uint64 freezeUntilNonce)"),
                  participant,
                  removalFee,
                  freezeUntilNonce
                )
              )
            ),
            signatures[i]
          )
        );
      }

      // If the votes of these holders doesn't meet the required participation threshold, throw
      // Guaranteed to be positive as all votes have been for so far
      if (uint112(netVotes(id)) < requiredParticipation()) {
        // Uses an ID of type(uint256).max since this proposal doesn't have an ID yet
        // While we have an id variable, if this transaction reverts, it'll no longer be valid
        // We could also use 0 yet that would overlap with an actual proposal
        revert NotEnoughParticipation(type(uint256).max, uint112(netVotes(id)), requiredParticipation());
      }

      // Freeze the token until this proposal completes, with an extra 1 day buffer
      // for someone to call completeProposal
      IFrabricERC20(erc20).freeze(participant, uint64(block.timestamp) + votingPeriod + queuePeriod + uint64(1 days));
    }
  }

  // Has an empty body as it doesn't have to be overriden
  function _participantRemoval(address /*participant*/) internal virtual {}
  // Has to be overriden
  function _completeSpecificProposal(uint256 id, uint256 proposalType) internal virtual;

  // Re-entrancy isn't a concern due to completeProposal being safe from re-entrancy
  // That's the only thing which should call this
  function _completeProposal(uint256 id, uint16 _pType, bytes calldata data) internal override {
    if (_isCommonProposal(_pType)) {
      CommonProposalType pType = CommonProposalType(_pType ^ commonProposalBit);
      if (pType == CommonProposalType.Paper) {
        // NOP as the DAO emits ProposalStateChange which is all that's needed for this

      } else if (pType == CommonProposalType.Upgrade) {
        Upgrade storage upgrade = _upgrades[id];
        IFrabricBeacon(upgrade.beacon).upgrade(upgrade.instance, upgrade.version, upgrade.code, upgrade.data);
        delete _upgrades[id];

      } else if (pType == CommonProposalType.TokenAction) {
        TokenAction storage action = _tokenActions[id];
        if (action.amount == 0) {
          (uint256 i) = abi.decode(data, (uint256));
          // cancelOrder returns a bool of our own order was cancelled or merely *an* order was cancelled
          if (!IIntegratedLimitOrderDEXCore(action.token).cancelOrder(action.price, i)) {
            // Uses address(0) as it's unknown who this trader was
            revert NotOrderTrader(address(this), address(0));
          }
        } else {
          bool auction = action.target == IFrabricERC20(erc20).auction();
          if (!auction) {
            if (action.mint) {
              IFrabricERC20(erc20).mint(action.target, action.amount);
            // The ILO DEX doesn't require transfer or even approve
            } else if (action.price == 0) {
              IERC20(action.token).safeTransfer(action.target, action.amount);
            }
          } else if (action.mint) {
            // If minting to sell at Auction, mint to sell as the Auction contract uses transferFrom
            IFrabricERC20(erc20).mint(address(this), action.amount);
          }

          // Not else to allow direct mint + sell
          if (action.price != 0) {
            // These orders cannot be cancelled at this time without the DAO wash trading
            // through the order, yet that may collide with others orders at the same price
            // point, so this isn't actually a viable method
            IIntegratedLimitOrderDEXCore(action.token).sell(action.price, action.amount / (10 ** IERC20Metadata(action.token).decimals()));

          // Technically, TokenAction could not acknowledge Auction
          // By transferring the tokens to another contract, the Auction can be safely created
          // This is distinct from the ILO DEX as agreement is needed on what price to list at
          // The issue is that the subcontract wouldn't know who transferred it tokens,
          // so it must have an owner for its funds. This means creating a new contract per Frabric/Thread
          // (or achieving global ERC777 adoptance yet that would be incredibly problematic for several reasons)
          // The easiest solution is just to write a few lines into this contract to handle it
          } else if (auction) {
            IERC20(action.token).safeIncreaseAllowance(action.target, action.amount);
            IAuctionCore(action.target).list(
              address(this),
              action.token,
              // Use our ERC20's DEX token as the Auction token to receive
              IIntegratedLimitOrderDEXCore(erc20).tradeToken(),
              action.amount,
              1,
              uint64(block.timestamp),
              // A longer time period can be decided on and utilized via the above method
              1 weeks
            );
          }
        }
        delete _tokenActions[id];

      } else if (pType == CommonProposalType.ParticipantRemoval) {
        Removal storage removal = _removals[id];
        IFrabricERC20(erc20).remove(removal.participant, removal.fee);
        _participantRemoval(removal.participant);
        delete _removals[id];

      } else {
        revert UnhandledEnumCase("FrabricDAO _completeProposal CommonProposal", _pType);
      }

    } else {
      _completeSpecificProposal(id, _pType);
    }
  }
}

