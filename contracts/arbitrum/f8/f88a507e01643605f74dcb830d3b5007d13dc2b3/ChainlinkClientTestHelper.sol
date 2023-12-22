// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ChainlinkClient.sol";
import "./Chainlink.sol";

contract ChainlinkClientTestHelper is ChainlinkClient {

  using Chainlink for Chainlink.Request;

  uint256 public constant ARBITRUM_MAINNET = 42161;
  uint256 public constant ARBITRUM_GOERLI = 421613;
  IArbSys public constant ARB_SYS = IArbSys(address(100));

  constructor(address _link, address _oracle) {
    setChainlinkToken(_link);
    setChainlinkOracle(_oracle);
  }

  function getBlockNumber() internal view returns (uint) {
    if (block.chainid == ARBITRUM_MAINNET || block.chainid == ARBITRUM_GOERLI) {
      return ARB_SYS.arbBlockNumber();
    }

    return block.number;
  }


  event Request(bytes32 id, address callbackAddress, bytes4 callbackfunctionSelector, bytes data);
  event LinkAmount(uint256 amount);
  event DataReceived(bytes32 data);

  function publicNewRequest(
    bytes32 _id,
    address _address,
    bytes memory _fulfillmentSignature
  ) public {
    Chainlink.Request memory req = buildChainlinkRequest(_id, _address, bytes4(keccak256(_fulfillmentSignature)));
    emit Request(req.id, req.callbackAddress, req.callbackFunctionId, req.buf.buf);
  }

  function publicRequest(
    bytes32 _id,
    address _address,
    bytes memory _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory req = buildChainlinkRequest(_id, _address, bytes4(keccak256(_fulfillmentSignature)));
    sendChainlinkRequest(req, _wei);
  }

  function publicRequestRunTo(
    address _oracle,
    bytes32 _id,
    address _address,
    bytes memory _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory run = buildChainlinkRequest(_id, _address, bytes4(keccak256(_fulfillmentSignature)));
    sendChainlinkRequestTo(_oracle, run, _wei);
  }

  function publicRequestRunTo2(
    address _oracle,
    bytes32 _id,
    address _address,
    string memory _from, string memory _to,
    bytes memory _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory run = buildChainlinkRequest(_id, _address, bytes4(keccak256(_fulfillmentSignature)));
    run.add("from", _from);
    run.add("to", _to);
    sendChainlinkRequestTo(_oracle, run, _wei);
  }

  function publicRequestRunTo3(
    address _oracle,
    bytes32 _id,
    address _address,
    string memory _from, string memory _to,
    bytes4  _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory run = buildChainlinkRequest(_id, _address, _fulfillmentSignature);
    run.add("from", _from);
    run.add("to", _to);
    sendChainlinkRequestTo(_oracle, run, _wei);
  }


  function publicRequestRunToLookbacks(
    address _oracle,
    bytes32 _idLimit,
    bytes32 _idMarket,
    address _address,
    string memory _from, string memory _to,
    bytes4  _fulfillmentSignature,
    uint256 _wei
  ) public {

    // limit
    Chainlink.Request memory run = buildChainlinkRequest(_idLimit, _address, _fulfillmentSignature);
    run.add("from", _from);
    run.add("to", _to);
    run.addUint("fromBlock", 0);
    sendChainlinkRequestTo(_oracle, run, _wei);


    // limit far back
    Chainlink.Request memory run2 = buildChainlinkRequest(_idLimit, _address, _fulfillmentSignature);
    run2.add("from", _from);
    run2.add("to", _to);
    run2.addUint("fromBlock", getBlockNumber() / 2);
    sendChainlinkRequestTo(_oracle, run2, _wei);

    // limit recent
    Chainlink.Request memory run3 = buildChainlinkRequest(_idLimit, _address, _fulfillmentSignature);
    run3.add("from", _from);
    run3.add("to", _to);
    run3.addUint("fromBlock", getBlockNumber() - 4);
    sendChainlinkRequestTo(_oracle, run3, _wei);

    // limit future to emulate slow rpc
    Chainlink.Request memory run4 = buildChainlinkRequest(_idLimit, _address, _fulfillmentSignature);
    run4.add("from", _from);
    run4.add("to", _to);
    run4.addUint("fromBlock", getBlockNumber() * 2);
    sendChainlinkRequestTo(_oracle, run4, _wei);


    // market
    Chainlink.Request memory run5 = buildChainlinkRequest(_idMarket, _address, _fulfillmentSignature);
    run5.add("from", _from);
    run5.add("to", _to);
    sendChainlinkRequestTo(_oracle, run5, _wei);
  }

  function publicRequestOracleData(
    bytes32 _id,
    bytes memory _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory req = buildOperatorRequest(_id, bytes4(keccak256(_fulfillmentSignature)));
    sendOperatorRequest(req, _wei);
  }

  function publicRequestOracleDataFrom(
    address _oracle,
    bytes32 _id,
    bytes memory _fulfillmentSignature,
    uint256 _wei
  ) public {
    Chainlink.Request memory run = buildOperatorRequest(_id, bytes4(keccak256(_fulfillmentSignature)));
    sendOperatorRequestTo(_oracle, run, _wei);
  }

  function publicCancelRequest(
    bytes32 _requestId,
    uint256 _payment,
    bytes4 _callbackFunctionId,
    uint256 _expiration
  ) public {
    cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
  }

  function publicChainlinkToken() public view returns (address) {
    return chainlinkTokenAddress();
  }

  function publicFulfillChainlinkRequest(bytes32 _requestId, bytes32) public {
    fulfillRequest(_requestId, bytes32(0));
  }

  function fulfillRequest(bytes32 _requestId, bytes32 data) public {
    emit DataReceived(data);
    validateChainlinkCallback(_requestId);
  }

  function selectoor2() public view returns (bytes32) {
    return this.fulfillRequest.selector;
  }

  function publicLINK(uint256 _amount) public {
    emit LinkAmount(LINK_DIVISIBILITY * _amount);
  }

  function publicOracleAddress() public view returns (address) {
    return chainlinkOracleAddress();
  }

  function publicAddExternalRequest(address _oracle, bytes32 _requestId) public {
    addChainlinkExternalRequest(_oracle, _requestId);
  }
}
interface IArbSys {
  /**
   * @notice Get internal version number identifying an ArbOS build
     * @return version number as int
     */
  function arbOSVersion() external pure returns (uint);

  function arbChainID() external view returns (uint);

  /**
   * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
  function arbBlockNumber() external view returns (uint);

  /**
   * @notice Send given amount of Eth to dest from sender.
     * This is a convenience function, which is equivalent to calling sendTxToL1 with empty calldataForL1.
     * @param destination recipient address on L1
     * @return unique identifier for this L2-to-L1 transaction.
     */
  function withdrawEth(address destination) external payable returns (uint);

  /**
   * @notice Send a transaction to L1
     * @param destination recipient address on L1
     * @param calldataForL1 (optional) calldata for L1 contract call
     * @return a unique identifier for this L2-to-L1 transaction.
     */
  function sendTxToL1(address destination, bytes calldata calldataForL1) external payable returns (uint);

  /**
   * @notice get the number of transactions issued by the given external account or the account sequence number of the given contract
     * @param account target account
     * @return the number of transactions issued by the given external account or the account sequence number of the given contract
     */
  function getTransactionCount(address account) external view returns (uint256);

  /**
   * @notice get the value of target L2 storage slot
     * This function is only callable from address 0 to prevent contracts from being able to call it
     * @param account target account
     * @param index target index of storage slot
     * @return stotage value for the given account at the given index
     */
  function getStorageAt(address account, uint256 index) external view returns (uint256);

  /**
   * @notice check if current call is coming from l1
     * @return true if the caller of this was called directly from L1
     */
  function isTopLevelCall() external view returns (bool);

  /**
   * @notice check if the caller (of this caller of this) is an aliased L1 contract address
     * @return true iff the caller's address is an alias for an L1 contract address
     */
  function wasMyCallersAddressAliased() external view returns (bool);

  /**
   * @notice return the address of the caller (of this caller of this), without applying L1 contract address aliasing
     * @return address of the caller's caller, without applying L1 contract address aliasing
     */
  function myCallersAddressWithoutAliasing() external view returns (address);

  /**
   * @notice map L1 sender contract address to its L2 alias
     * @param sender sender address
     * @param dest destination address
     * @return aliased sender address
     */
  function mapL1SenderContractAddressToL2Alias(address sender, address dest) external pure returns (address);

  /**
   * @notice get the caller's amount of available storage gas
     * @return amount of storage gas available to the caller
     */
  function getStorageGasAvailable() external view returns (uint);

  event L2ToL1Transaction(
    address caller,
    address indexed destination,
    uint indexed uniqueId,
    uint indexed batchNumber,
    uint indexInBatch,
    uint arbBlockNum,
    uint ethBlockNum,
    uint timestamp,
    uint callvalue,
    bytes data
  );
}

