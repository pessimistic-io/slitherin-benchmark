// SPDX-License-Identifier: AGPL-3.0

//                       .,,,,.
//               ,(%%%%%%%%%%%%%%%%%%#,
//           .#%%%%%%%%%%%%%%%%%%%%%%%%%%#,
//         (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(.
//       (%%%%%%%%%%%%%%%%%%%%%%%#*,,*/#%%%%%%%*
//     ,%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,*#%%%%%(.
//    *%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,*#%%%%%*
//   ,%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,,/%%%%%(.
//   /%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,*#%%%%%*
//   (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,,/%%%%%(.
//   (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(*,,,,,,,,,,,,,,*#%%%%%*
//   *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,,,(%%%%%#.
//    (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,,,(%%%%%%*
//     #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(,,,,,,,,,,,,,,*%%%&&&#.
//      *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%/,,,,,,,,,,,,,*%&&&==&*
//        (%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#*,,,,,,,,,,,,*#&=====(.
//          *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%(*,,,,,,,,,,,,/%=====&*
//            .(%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&%/,,,,,,,,,,,,/%&=====#.
//               *%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&%%#*,,,,,,,,,,,*#======&*
//                 .(%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&&=====&%(,,,,,,,,,,,*#%======#.
//                    *%%%%%%%%%%%%%%%%%%%%%%%%%%&&&&&===========%/,,,,,,,,,,,(%======&*
//                      .(%%%%%%%%%%%%%%%%%%%%&&&&&================&#*,,,,,,,,,,/%=======#.
//                         *%%%%%%%%%%%%%%%&&&&&&=====================%(,,,,,,,,,,*%&======&*
//                           .(%%%%%%%%%%&&&&&==========================&%/,,,,,,,,,*%========/
//                              *%%%%%&&&&&&===============================%#*,,,,,,,,(%=======%,
//                                .(&&&&&=====================================%#*,,,,,*%&=======&,
//                                  *%==========================================&%%##%==========%,
//                                     .(=========================================================(
//                                        *%======================================================%.
//                                          .(====================================================#.
//                                             *%=================================================(
//                                               .(==============================================%.
//                                                  *%==========================================&,
//                                                    .(=======================================%.
//                                                       *%===================================*
//                                                         .(==============================%,
//                                                            .(&=======================#,
//                                                                ,(%&===========%#*

pragma solidity ^0.8.0;

import "./VRFCoordinatorV2Interface.sol";
import "./VRFConsumerBaseV2.sol";
import "./ECDSA.sol";
import "./IFabricator.sol";
import "./verification_Auth.sol";

/// @title RaffleValidator
/// @author Ping
/// @notice Handles minting of PortalPills using either a direct sale, or raffle dependant on parcipants. In order to deposit, the signer must provide sign-off on your account.
/// @dev Explain to a developer any extra details
contract RaffleValidator is VRFConsumerBaseV2, Auth {
  VRFCoordinatorV2Interface private _coordinator;
  // WL SIGNING STATE
  // Everything for the WL signing
  // process.
  // In order to "Whitelist" somebody the validation signer
  // account has to sign on behalf of the account being whitelisted.
  // This Signature then needs to be provided along with the deposit in order
  // for the participant to add a deposit to the raffle.
  // Triggering the "whitelist disabled" circumvents this behavior.
  using ECDSA for bytes32;
  struct EIP712Domain {
    string name;
    string version;
    uint256 chainId;
    address verifyingContract;
  }
  struct Target {
    uint256 chainId;
    address wallet;
  }
  bytes32 private immutable _domainSeparator;
  bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
    keccak256(
      "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
  bytes32 private constant _TARGET_TYPEHASH =
    keccak256("Target(uint256 chainId,address wallet)");
  address private _validationSigner;

  // RAFFLE STATE
  uint256 private _tokenId;
  // Core instannce to eventuall mind the tokens to
  IFabricator public core;
  uint256 private _raffleCost;
  // Count of how many winners have already been selected
  uint256 private _winnersSelected;
  // Flag to prevent multiple randomness requests at once
  bool private _awaitingRandomness;
  address[] private _raffleTickets;
  // Basic boolean state handlers
  // Whether the raffle has concluded
  bool private _raffleEnded;
  // True if there were enough participants to run the raffle
  bool private _runRaffle;
  bool private _whitelistDisabled;
  // Total number of entries needed to trigger a raffle
  uint32 private immutable _raffleTrigger;
  mapping(address => uint256) public count;
  mapping(address => bool) public hasWon;
  mapping(address => bool) public hasClaimed;

  // RANDOMNESS STATE
  // TODO: Setup setters/getters for this
  // A reasonable default is 100000, but this value could be different
  // on other networks.
  uint32 public callbackGasLimit = 100000;
  // The default is 3, but you can set this higher.
  uint16 public requestConfirmations = 3;
  event RequestId(bytes32 requestId);
  uint64 public subscriptionId;
  bytes32 private _keyHash;

  constructor(
    IFabricator _core,
    address coordinator_,
    address signer_,
    uint256 raffleCost_,
    uint256 id,
    Authority auth,
    uint32 raffleTrigger_
  )
    VRFConsumerBaseV2(
      coordinator_ // VRF Coordinator
    )
    Auth(msg.sender, auth)
  {
    _tokenId = id;
    _raffleCost = raffleCost_;
    _coordinator = VRFCoordinatorV2Interface(coordinator_);
    core = _core;
    _validationSigner = signer_;
    _raffleTrigger = raffleTrigger_;
    _domainSeparator = _hashDomain(
      EIP712Domain({
        name: "SYNTH Validator",
        version: "1",
        chainId: _getChainID(),
        verifyingContract: address(this)
      })
    );
    //Create a new subscription when you deploy the contract.
  }

  // DEPOSIT FUNCTIONS

  /// @notice Deposit funds into the raffle.
  /// @param recipient A Target structure containing a wallet and chain ID for the whitelisted account
  /// @param v recovery identifier
  /// @param r signature part 1
  /// @param s signature part 2
  function addDeposit(
    Target calldata recipient,
    uint8 v,
    bytes32 r,
    bytes32 s // bytes calldata signature
  ) external payable {
    require(msg.value > _raffleCost, "Sorry, that's not enough for the raffle");
    require(!_raffleEnded, "Sorry raffle has ended");
    address signatureSigner = _hash(recipient).recover(v, r, s);
    require(signatureSigner == _validationSigner, "Invalid Signature");
    // prevent replay
    require(recipient.chainId == _getChainID(), "Invalid chainId");
    uint256 ticketCount = msg.value / _raffleCost;
    unchecked {
      for (uint8 i; i < ticketCount; i++) {
        _raffleTickets.push(recipient.wallet);
      }
      count[recipient.wallet] += ticketCount;
    }
  }

  /// @notice Adds a deposit without whitelist
  /// @param recipient target address to give raffle tickets to
  function addDepositNoWL(address recipient) external payable {
    require(!_raffleEnded, "Sorry raffle has ended");
    require(_whitelistDisabled, "Sorry, whitelist is enabled");
    uint256 ticketCount = msg.value / _raffleCost;
    unchecked {
      for (uint8 i; i < ticketCount; i++) {
        _raffleTickets.push(recipient);
      }
      count[recipient] += ticketCount;
    }
  }

  /// @notice Refund a series of raffle tickets
  /// @dev Neccesary to know what indices the tickets were added into
  /// @param indices List of tickets to refund
  function removeDeposits(uint256[] calldata indices) external {
    require(!hasWon[msg.sender], "Sorry, no refunds for winners");
    unchecked {
      for (uint8 i; i < indices.length; i++) {
        _removeDeposit(indices[i]);
      }
    }
    uint256 baseCost = indices.length * _raffleCost;
    uint256 returnValue = _raffleEnded ? baseCost - _raffleCost : baseCost;
    (bool success, ) = msg.sender.call{value: returnValue}("");
    require(success, "Transfer failed.");
  }

  // CLAIM FUNCTIONS

  /// @notice Gives the raffle winner their portalpill
  /// @dev Explain to a developer any extra details
  /// @param winner Account to claim winning portalpills to
  function claim(address winner) external {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    require(hasWon[winner], "Can only claim for winners");
    require(!hasClaimed[winner], "Can only claim once");
    idReturn[0] = _tokenId;
    quantityReturn[0] = 1;
    core.modularMintCallback(winner, idReturn, quantityReturn, "");
    hasClaimed[winner] = true;
  }

  /// @notice If raffle doesn't run, allows direct redemption of portalpills
  /// @dev Explain to a developer any extra details
  function directClaim() external {
    require(
      _runRaffle == false && _raffleEnded == true,
      "Direct claim only valid if raffle didn't run"
    );
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    require(!hasClaimed[msg.sender], "Can only claim once");
    idReturn[0] = _tokenId;
    quantityReturn[0] = count[msg.sender];
    core.modularMintCallback(msg.sender, idReturn, quantityReturn, "");
    hasClaimed[msg.sender] = true;
  }

  // ADMIN FUNCTIONS

  function endRaffle() external requiresAuth {
    if (_raffleTickets.length > _raffleTrigger) {
      _runRaffle = true;
    }
    _raffleEnded = true;
  }

  function disableWhitelist() external requiresAuth {
    _whitelistDisabled = true;
  }

  function setChainlink(
    bytes32 keyHash_,
    uint32 _callbackGasLimit,
    uint16 _requestConfirmations,
    uint64 _subscriptionId
  ) public requiresAuth {
    _keyHash = keyHash_;
    callbackGasLimit = _callbackGasLimit;
    requestConfirmations = _requestConfirmations;
    subscriptionId = _subscriptionId;
  }

  /// @notice Called from Admin to process _count winners in the raffle.
  /// @dev Explain to a developer any extra details
  /// @param _count Number of winners to select
  function processRaffle(uint32 _count) public requiresAuth {
    require(_runRaffle, "Must have enough to run raffle");
    require(
      _winnersSelected + _count <= _raffleTrigger,
      "Too many winners would be selected"
    );
    require(
      _awaitingRandomness == false,
      "Wait until randomness has been processed to request more"
    );
    _coordinator.requestRandomWords(
      _keyHash,
      subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      _count
    );
    _awaitingRandomness = true;
  }

  /// INTERNAL FUNCTIONS

  function _hash(Target memory recipient) internal view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          _domainSeparator,
          _hashRecipient(recipient)
        )
      );
  }

  function _hashRecipient(Target memory recipient)
    internal
    pure
    returns (bytes32)
  {
    return
      keccak256(
        abi.encode(_TARGET_TYPEHASH, recipient.chainId, recipient.wallet)
      );
  }

  function _removeDeposit(uint256 index) internal {
    require(
      msg.sender == _raffleTickets[index],
      "Sorry you're requesting a refund for a ticket you didn't buy"
    );
    count[msg.sender] -= 1;
    _raffleTickets[index] = _raffleTickets[_raffleTickets.length - 1];
    _raffleTickets.pop();
  }

  // Extract eip721 into abstraction
  function _hashDomain(EIP712Domain memory eip712Domain)
    private
    pure
    returns (bytes32)
  {
    return
      keccak256(
        abi.encode(
          _EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(eip712Domain.name)),
          keccak256(bytes(eip712Domain.version)),
          eip712Domain.chainId,
          eip712Domain.verifyingContract
        )
      );
  }

  function _getChainID() private view returns (uint256) {
    uint256 id;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      id := chainid()
    }
    return id;
  }

  // solhint-disable-next-line
  function fulfillRandomWords(uint256, uint256[] memory randomWords)
    internal
    override
  {
    require(_awaitingRandomness == true, "Must trigger processRaffle first");
    // TODO: Confirm abscence of over/under flow states
    for (uint8 i; i < randomWords.length; i++) {
      uint256 winner = ((randomWords[i] % _raffleTickets.length) -
        _winnersSelected) + _winnersSelected;
      if (hasWon[_raffleTickets[winner]]) {
        _raffleTickets[winner] = _raffleTickets[_raffleTickets.length - 1];
        _raffleTickets.pop();
      } else {
        _raffleTickets[_winnersSelected] = _raffleTickets[winner];
        _winnersSelected++;
        hasWon[_raffleTickets[winner]] = true;
      }
    }
    _awaitingRandomness == false;
  }
}

