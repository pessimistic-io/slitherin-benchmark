// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract TfiFeedRegistry is Initializable, OwnableUpgradeable {
  bytes32 constant SET = "set";
  bytes32 constant GET = "get";
  bytes32 constant PROXY = "proxy";

  struct RoundData {
    int256 answer;
    uint256 startedAt;
    uint256 updatedAt;
  }

  uint80 public latestRound;
  mapping (bytes32 => mapping(uint80 => RoundData)) private data;
  mapping (bytes32 => mapping(bytes32 => mapping(address => bool)))
  private permissions;

/**
 * @dev Emitted when data is set for a specific round of a price feed.
 * @param dataType The dataType for the price feed.
 * @param roundId The ID of the round.
 * @param answer The answer for the round.
 * @param startedAt The timestamp for when the round started.
 * @param updatedAt The timestamp for when the round was last updated.
 */

  event RoundDataSet(
    bytes32 indexed dataType,
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt
  );

/**
 * @dev Emitted when access permissions are set for a
 *      specific role, dataType, and address.
 * @param role The role for the permissions.
 * @param dataType The dataType for the permissions.
 * @param user The address the permissions are being set for.
 * @param value The value the permissions are being set to.
 */

  event AccessSet(
    bytes32 indexed role,
    bytes32 indexed dataType,
    address indexed user,
    bool value
  );

/**
 * @dev Modifies a function to restrict access based on the
 *      sender's permission level for a given role and dataType.
 * @param role The role to check access for.
 * @param dataType The dataType to check access for.
 * @param sender The address of the sender.
 */

  modifier onlyAccess(bytes32 role, bytes32 dataType, address sender) {
    require(
      hasAccess(role, dataType, address(0x0)) ||
      hasAccess(role, dataType, msg.sender) ||
      (
        hasAccess(PROXY, dataType, msg.sender) &&
        hasAccess(role, dataType, sender)
      ),
      "Access denied"
    );
    _;
  }

/**
 * @dev Modifies a function to restrict access to setting
 *      round data based on the sender's permission level
 *      for a given dataType.
 * @param sender The address of the sender.
 * @param dataType The dataType to check access for.
 */

  modifier onlySetAccess(address sender, bytes32 dataType) {
    require(hasAccess(SET, dataType, sender), "Access denied");
    _;
  }

  function initialize(
  ) public initializer {
    __Ownable_init();
  }

/**
 * @dev Returns the data for a specific round of a price feed.
 * @param dataType The dataType for the price feed.
 * @param roundId The ID of the round to get data for.
 * @param sender The address of the sender.
 * @return roundId The ID of the round.
 * @return answer The answer for the round.
 * @return startedAt The timestamp for when the round started.
 * @return updatedAt The timestamp for when the round was last updated.
 * @return answeredInRound The ID of the latest round.
 */

  function getRoundData(bytes32 dataType, uint80 roundId_, address sender)
  public
  view
  virtual
  onlyAccess(GET, dataType, sender)
  returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  )
  {
    RoundData memory rd = data[dataType][roundId_];
    return (roundId_, rd.answer, rd.startedAt, rd.updatedAt, latestRound);
  }

/**
 * @dev Returns the data for the latest round of a price feed.
 * @param dataType The dataType for the price feed.
 * @param sender The address of the sender.
 * @return roundId The ID of the latest round.
 * @return answer The answer for the latest round.
 * @return startedAt The timestamp for when the latest round started.
 * @return updatedAt The timestamp for when the latest round was last updated.
 * @return answeredInRound The ID of the latest round.
 */

  function latestRoundData(bytes32 dataType, address sender)
  external
  view
  virtual
  onlyAccess(GET, dataType, sender)
  returns (
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  )
  {
    return getRoundData(dataType, latestRound, sender);
  }

/**
 * @dev Sets the data for a specific round of a price feed.
 * @param dataType The dataType for the price feed.
 * @param roundId The ID of the round to set data for.
 * @param answer The answer for the round.
 * @param startedAt The timestamp for when the round started.
 * @param updatedAt The timestamp for when the round was last updated.
 */

  function setRoundData(
    bytes32 dataType,
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt
  ) external virtual onlySetAccess(msg.sender, dataType) {
    latestRound = roundId;
    data[dataType][roundId] = RoundData(answer, startedAt, updatedAt);
    emit RoundDataSet(dataType, roundId, answer, startedAt, updatedAt);
  }

/**
 * @dev Sets the access permissions for a specific role, dataType, and address.
 * @param role The role for the permissions.
 * @param dataType The dataType for the permissions.
 * @param client The address to set permissions for.
 * @param value The value to set the permissions to.
 */

  function setAccess(
    bytes32 role,
    bytes32 dataType,
    address client,
    bool value
  ) external onlyOwner {
    permissions[role][dataType][client] = value;
    emit AccessSet(role, dataType, client, value);
  }

/**
 * @dev Returns whether a given address has access to a specific role and dataType.
 * @param role The role to check access for.
 * @param dataType The dataType to check access for.
 * @param client The address to check access for.
 * @return Whether the address has access.
 */

  function hasAccess(
    bytes32 role,
    bytes32 dataType,
    address client
  ) private view returns (bool) {
    return permissions[role][dataType][client];
  }

  function version() external pure returns (uint256) {
    return 202304210;
  }
}

