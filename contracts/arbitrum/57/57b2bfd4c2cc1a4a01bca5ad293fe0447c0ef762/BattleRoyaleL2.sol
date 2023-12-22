// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AxelarExecutable } from "./AxelarExecutable.sol";
import { Auth } from "./Auth.sol";
import { MerkleProof } from "./MerkleProof.sol";
import { Pausable } from "./Pausable.sol";
import { Card } from "./Card.sol";
import { Stance } from "./Stance.sol";
import { TicketPrices } from "./BattleRoyaleL1.sol";
import { Card } from "./Card.sol";
import { OperationType } from "./OperationType.sol";

interface IFight {
  function fight(
    address calcAddress,
    Card memory attacker,
    Card memory defender,
    Stance stance,
    Stance defenderStance,
    uint256 seed
  ) external pure returns (uint256);
  function readLog(uint256 log)
    external
    pure
    returns (bool, bool, uint256, uint16[4] memory, bool[4] memory);
}

struct BattleRoyaleHistory {
  uint256 index;
  QueuedFighter[] fighters;
  uint256[] logs;
  uint256 timestamp;
  address betAsset;
  TicketPrices ticketPrice;
  bool[] combatAttackerWinner;
}

struct QueuedFighter {
  bytes32 nftHash;
  address collection;
  Card card;
  Stance stance;
  address owner;
}

struct LogIndex {
  uint256[] logs;
  uint256 timestamp;
  uint256 shuffleSeed;
}

contract BattleRoyaleL2 is AxelarExecutable, Auth, Pausable {
  string validSourceChain;
  bytes32 validSourceChainHash;
  string validSourceAddress;
  bytes32 validSourceAddressHash;
  IFight fightEngine;
  address damageCalc;

  uint8 public constant BATTLE_SIZE = 16;

  mapping(address => bytes32) private merkleRoots;

  error BadOrigin();
  error BadMerkleProof();
  error NftAlreadyInQueue();
  error BattleRoyaleNotReady();

  struct QueueIndexes {
    uint256 start;
    uint256 end;
  }

  event MessageProcessed(OperationType _operationType);

  mapping(address => mapping(TicketPrices => QueuedFighter[])) public queuedFighters;
  mapping(address => mapping(TicketPrices => uint256)) public queueIndex;
  mapping(address => mapping(TicketPrices => mapping(uint256 => LogIndex))) public battleLogs;

  constructor(
    address _gateway,
    string memory _validSourceChain,
    string memory _validSourceAddress,
    address _fightEngine,
    address _damageCalc
  ) AxelarExecutable(_gateway) Auth(msg.sender) {
    validSourceChain = _validSourceChain;
    validSourceChainHash = keccak256(abi.encodePacked(_validSourceChain));
    validSourceAddress = _validSourceAddress;
    validSourceAddressHash = keccak256(abi.encodePacked(_validSourceAddress));
    fightEngine = IFight(_fightEngine);
    damageCalc = _damageCalc;
  }

  function _execute(
    string calldata _sourceChain,
    string calldata _sourceAddress,
    bytes calldata _payload
  ) internal override {
    if (keccak256(abi.encodePacked(_sourceChain)) != validSourceChainHash) {
      revert BadOrigin();
    }

    if (keccak256(abi.encodePacked(_sourceAddress)) != validSourceAddressHash) {
      revert BadOrigin();
    }

    (OperationType operationType, bytes memory payload) =
      abi.decode(_payload, (OperationType, bytes));

    if (operationType == OperationType.ENQUEUE) {
      _enqueue(payload);
    } else if (operationType == OperationType.EXECUTE) {
      _executeNextBattleRoyale(payload);
    }

    emit MessageProcessed(operationType);
  }

  function _executeNextBattleRoyale(bytes memory _payload) private whenNotPaused {
    (address _asset, TicketPrices _ticketPrice) = abi.decode(_payload, (address, TicketPrices));

    uint256 queueStartIndex = queueIndex[_asset][_ticketPrice];
    uint256 currentQueueIndex = queueStartIndex / BATTLE_SIZE;
    if (!_canBattleRoyaleBeExecuted(queueStartIndex, _asset, _ticketPrice)) {
      revert BattleRoyaleNotReady();
    }
    uint256 shuffleSeed =
      uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), currentQueueIndex)));
    QueuedFighter[] memory fighters =
      _shuffle(_getQueue(queueStartIndex, _asset, _ticketPrice), shuffleSeed);
    battleLogs[_asset][_ticketPrice][currentQueueIndex].timestamp = block.timestamp;
    battleLogs[_asset][_ticketPrice][currentQueueIndex].shuffleSeed = shuffleSeed;
    QueuedFighter memory winner = _fightRound(fighters, currentQueueIndex, _asset, _ticketPrice)[0];
    gateway.callContract(
      validSourceChain,
      validSourceAddress,
      abi.encode(winner.owner, _asset, _ticketPrice, BATTLE_SIZE)
    );
    queueIndex[_asset][_ticketPrice] += BATTLE_SIZE;
  }

  function _fightRound(
    QueuedFighter[] memory _fighters,
    uint256 _brIndex,
    address _asset,
    TicketPrices _ticketPrice
  ) private whenNotPaused returns (QueuedFighter[] memory) {
    uint256 resultSize = _fighters.length / 2;
    QueuedFighter[] memory winners = new QueuedFighter[](resultSize);
    for (uint256 i = 0; i < resultSize; i++) {
      uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), i)));
      QueuedFighter memory attacker = _fighters[i * 2];
      QueuedFighter memory defender = _fighters[i * 2 + 1];
      uint256 log = fightEngine.fight(
        // move damage calc to fight?
        damageCalc,
        attacker.card,
        defender.card,
        attacker.stance,
        defender.stance,
        seed
      );
      battleLogs[_asset][_ticketPrice][_brIndex].logs.push(log);

      (, bool attackerVictory,,,) = fightEngine.readLog(log);
      winners[i] = attackerVictory ? attacker : defender;
    }
    if (resultSize == 1) {
      return winners;
    } else {
      return _fightRound(winners, _brIndex, _asset, _ticketPrice);
    }
  }

  function canBattleRoyaleBeExecuted(address _asset, TicketPrices _ticketPrice)
    external
    view
    returns (bool)
  {
    uint256 queueStartIndex = queueIndex[_asset][_ticketPrice];
    return _canBattleRoyaleBeExecuted(queueStartIndex, _asset, _ticketPrice);
  }

  function _canBattleRoyaleBeExecuted(
    uint256 _queueStartIndex,
    address _asset,
    TicketPrices _ticketPrice
  ) private view returns (bool) {
    return queuedFighters[_asset][_ticketPrice].length - _queueStartIndex >= BATTLE_SIZE;
  }

  function _enqueue(bytes memory _payload) private whenNotPaused {
    (
      address betAsset,
      TicketPrices ticketPrice,
      Card memory fighter,
      bytes32[] memory cardProof,
      Stance stance,
      address collection,
      uint256 nftId,
      address nftOwner
    ) = abi.decode(
      _payload, (address, TicketPrices, Card, bytes32[], Stance, address, uint256, address)
    );
    if (
      !MerkleProof.verify(
        cardProof,
        merkleRoots[collection],
        keccak256(bytes.concat(keccak256(abi.encode(nftId, fighter))))
      )
    ) {
      revert BadMerkleProof();
    }
    bytes32 nftHash = keccak256(abi.encode(collection, nftId));

    if (!_canQueue(nftHash, betAsset, ticketPrice)) {
      revert NftAlreadyInQueue();
    }
    queuedFighters[betAsset][ticketPrice].push(
      QueuedFighter(nftHash, collection, fighter, stance, nftOwner)
    );
  }

  function canQueue(bytes32 _nftHash, address _betAsset, TicketPrices _ticketPrice)
    external
    view
    returns (bool)
  {
    return _canQueue(_nftHash, _betAsset, _ticketPrice);
  }

  function _canQueue(bytes32 _nftHash, address _betAsset, TicketPrices _ticketPrice)
    private
    view
    returns (bool)
  {
    QueuedFighter[] storage fullQueue = queuedFighters[_betAsset][_ticketPrice];
    uint256 nextQueueIndex = fullQueue.length / BATTLE_SIZE;
    uint256 nextQueueStartIndex = nextQueueIndex * BATTLE_SIZE;
    for (uint256 i = nextQueueStartIndex; i < fullQueue.length; i++) {
      if (fullQueue[i].nftHash == _nftHash) {
        return false;
      }
    }
    return true;
  }

  function getCurrentQueue(address _betAsset, TicketPrices _ticketPrice)
    public
    view
    returns (QueuedFighter[] memory)
  {
    uint256 index = queueIndex[_betAsset][_ticketPrice];
    return _getQueue(index, _betAsset, _ticketPrice);
  }

  function getMostRecentHistory(uint256 _numOfItems, address _betAsset, TicketPrices _ticketPrice)
    public
    view
    returns (BattleRoyaleHistory[] memory)
  {
    uint256 currentIndex = queueIndex[_betAsset][_ticketPrice];
    uint256 numberOfPastBattles = currentIndex / BATTLE_SIZE;
    uint256 numberOfHistory = _min(numberOfPastBattles, _numOfItems);
    BattleRoyaleHistory[] memory history = new BattleRoyaleHistory[](numberOfHistory);
    for (uint256 i = 0; i < numberOfHistory; i++) {
      uint256 index = currentIndex - (i + 1) * BATTLE_SIZE;
      LogIndex storage logIndex = battleLogs[_betAsset][_ticketPrice][index / BATTLE_SIZE];
      bool[] memory attackerWinner = new bool[](logIndex.logs.length);
      for (uint256 j = 0; j < logIndex.logs.length; j++) {
        (, bool attackerVictory,,,) = fightEngine.readLog(logIndex.logs[j]);
        attackerWinner[j] = attackerVictory;
      }
      history[i] = BattleRoyaleHistory(
        index,
        _shuffle(_getQueue(index, _betAsset, _ticketPrice), logIndex.shuffleSeed),
        logIndex.logs,
        logIndex.timestamp,
        _betAsset,
        _ticketPrice,
        attackerWinner
      );
    }
    return history;
  }

  function getQueueByIndex(uint256 _index, address _betAsset, TicketPrices _ticketPrice)
    public
    view
    returns (QueuedFighter[] memory)
  {
    uint256 startIndex = _index * BATTLE_SIZE;
    return _getQueue(startIndex, _betAsset, _ticketPrice);
  }

  function _getQueue(uint256 _startIndex, address _betAsset, TicketPrices _ticketPrice)
    private
    view
    returns (QueuedFighter[] memory)
  {
    uint256 idx = 0;
    uint256 limit = _min(_startIndex + BATTLE_SIZE, queuedFighters[_betAsset][_ticketPrice].length);
    uint256 returnArrayLength = limit - _startIndex;
    QueuedFighter[] memory queue = new QueuedFighter[](returnArrayLength);
    for (uint256 i = _startIndex; i < limit; i++) {
      queue[idx] = (queuedFighters[_betAsset][_ticketPrice][i]);
      idx++;
    }
    return queue;
  }

  function _shuffle(QueuedFighter[] memory _fighters, uint256 _seed)
    private
    pure
    returns (QueuedFighter[] memory)
  {
    uint256 n = _fighters.length;
    for (uint256 i = n - 1; i > 0; i--) {
      uint8 singleByte = uint8(_seed >> (i % 32 * 8));
      uint256 j = singleByte % (i + 1);
      QueuedFighter memory tmp = _fighters[i];
      _fighters[i] = _fighters[j];
      _fighters[j] = tmp;
    }
    return _fighters;
  }

  function setMerkleRoot(address _collection, bytes32 _root) external authorized {
    merkleRoots[_collection] = _root;
  }

  function setValidSourceChain(string memory _validSourceChain) external authorized {
    validSourceChain = _validSourceChain;
    validSourceChainHash = keccak256(abi.encodePacked(_validSourceChain));
  }

  function setValidSourceAddress(string memory _validSourceAddress) external authorized {
    validSourceAddress = _validSourceAddress;
    validSourceAddressHash = keccak256(abi.encodePacked(_validSourceAddress));
  }

  function setFightEngine(address _fightEngine) external authorized {
    fightEngine = IFight(_fightEngine);
  }

  function setDamageCalc(address _damageCalc) external authorized {
    damageCalc = _damageCalc;
  }

  function pause(bool _paused) external authorized {
    if (_paused) {
      _pause();
    } else {
      _unpause();
    }
  }

  function _min(uint256 a, uint256 b) private pure returns (uint256) {
    return a < b ? a : b;
  }
}

