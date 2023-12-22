// SPDX-License-Identifier: BUSL-1.1

/**
 *
 * @title ArrngController.sol. Core contract for arrng, multi-chain
 * off-chain RNG with full on-chain (event) storage of data and signatures.
 *
 * No subscriptions, ERC20 tokens or funds held in escrow.
 *
 * No confusing parameters and hashes. Pay in native token for the
 * randomness you need.
 *
 * @author arrng https://arrng.io/
 *
 */

pragma solidity 0.8.19;

import {IArrngController} from "./IArrngController.sol";
import {IArrngConsumer} from "./IArrngConsumer.sol";
import {IENSReverseRegistrar} from "./IENSReverseRegistrar.sol";
import {IERC721} from "./IERC721.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Strings} from "./Strings.sol";

contract ArrngController is IArrngController, Ownable, IERC721Receiver {
  using Strings for uint176;

  // Minimum native token required for gas cost to serve RNG. Note that more
  // token for gas will be required, depending on prevailing gas conditions.
  // Excess token is refunded. An up to date estimate of native token required
  // for gas can be obtained from the api.arrng.io. See arrng.io for more details.
  uint176 public minimumNativeToken;

  // Request ID:
  uint64 public arrngRequestId;

  // Limit on number of returned numbers:
  uint16 public maximumNumberOfNumbers;

  // Address of the oracle:
  address payable public oracleAddress;

  // Address of the treasury
  address payable public treasuryAddress;

  // Address of the ENS reverse registrar to allow assignment of an ENS
  // name to this contract:
  IENSReverseRegistrar public ensReverseRegistrar;

  /**
   *
   * @dev constructor
   *
   * @param owner_: contract ownable owner
   *
   */
  constructor(address owner_) {
    _transferOwnership(owner_);
    maximumNumberOfNumbers = 100;
  }

  /**
   * -------------------------------------------------------------
   * @dev ADMINISTRATION
   * -------------------------------------------------------------
   */

  /**
   *
   * @dev setENSReverseRegistrar: set the ENS register address
   *
   * @param ensRegistrar_: ENS Reverse Registrar address
   *
   */
  function setENSReverseRegistrar(address ensRegistrar_) external onlyOwner {
    ensReverseRegistrar = IENSReverseRegistrar(ensRegistrar_);
    emit ENSReverseRegistrarSet(ensRegistrar_);
  }

  /**
   *
   * @dev setENSName: used to set reverse record so interactions with this contract
   * are easy to identify
   *
   * @param ensName_: string ENS name
   *
   */
  function setENSName(string memory ensName_) external onlyOwner {
    bytes32 ensNameHash = ensReverseRegistrar.setName(ensName_);
    emit ENSNameSet(ensName_, ensNameHash);
    (ensName_);
  }

  /**
   *
   * @dev setMinimumNativeToken: set a new value of required native token for gas
   *
   * @param minNativeToken_: the new minimum native token per call
   *
   */
  function setMinimumNativeToken(uint176 minNativeToken_) external onlyOwner {
    minimumNativeToken = minNativeToken_;
    emit MinimumNativeTokenSet(minNativeToken_);
  }

  /**
   *
   * @dev setMaximumNumberOfNumbers: set a new max number of numbers
   *
   * @param maxNumbersPerTxn_: the new max requested numbers
   *
   */
  function setMaximumNumberOfNumbers(
    uint16 maxNumbersPerTxn_
  ) external onlyOwner {
    maximumNumberOfNumbers = maxNumbersPerTxn_;
    emit MaximumNumberOfNumbersSet(maxNumbersPerTxn_);
  }

  /**
   *
   * @dev setOracleAddress: set a new oracle address
   *
   * @param oracle_: the new oracle address
   *
   */
  function setOracleAddress(address payable oracle_) external onlyOwner {
    require(oracle_ != address(0), "Oracle address cannot be address(0)");
    oracleAddress = oracle_;
    emit OracleAddressSet(oracle_);
  }

  /**
   *
   * @dev setTreasuryAddress: set a new treasury address
   *
   * @param treasury_: the new treasury address
   *
   */
  function setTreasuryAddress(address payable treasury_) external onlyOwner {
    require(treasury_ != address(0), "Treasury address cannot be address(0)");
    treasuryAddress = treasury_;
    emit TreasuryAddressSet(treasury_);
  }

  /**
   *
   * @dev withdrawNativeToken: pull native token to the treasuryAddress
   *
   * @param amount_: amount to withdraw
   *
   */
  function withdrawNativeToken(uint256 amount_) external onlyOwner {
    require(
      treasuryAddress != address(0),
      "Cannot withdraw to a treasury at address(0)"
    );
    _processPayment(treasuryAddress, amount_);
  }

  /**
   *
   * @dev withdrawERC20: pull ERC20 tokens to the treasuryAddress
   *
   * @param erc20Address_: the contract address for the token
   * @param amount_: amount to withdraw
   *
   */
  function withdrawERC20(
    address erc20Address_,
    uint256 amount_
  ) external onlyOwner {
    require(
      treasuryAddress != address(0),
      "Cannot withdraw to a treasury at address(0)"
    );
    IERC20(erc20Address_).transfer(treasuryAddress, amount_);
  }

  /**
   *
   * @dev withdrawERC721: Pull ERC721s (likely only the ENS
   * associated with this contract) to the treasuryAddress.
   *
   * @param erc721Address_: The token contract for the withdrawal
   * @param tokenIDs_: the list of tokenIDs for the withdrawal
   *
   */
  function withdrawERC721(
    address erc721Address_,
    uint256[] memory tokenIDs_
  ) external onlyOwner {
    require(
      treasuryAddress != address(0),
      "Cannot withdraw to a treasury at address(0)"
    );
    for (uint256 i = 0; i < tokenIDs_.length; ) {
      IERC721(erc721Address_).transferFrom(
        address(this),
        treasuryAddress,
        tokenIDs_[i]
      );
      unchecked {
        ++i;
      }
    }
  }

  /**
   *
   * @dev onERC721Received: allow transfer from owner (for the ENS token).
   *
   * @param from_: used to check this is only from the contract owner
   *
   */
  function onERC721Received(
    address,
    address from_,
    uint256,
    bytes memory
  ) external view returns (bytes4) {
    if (from_ == owner()) {
      return this.onERC721Received.selector;
    } else {
      return ("");
    }
  }

  /**
   * -------------------------------------------------------------
   * @dev PROCESS REQUESTS
   * -------------------------------------------------------------
   */

  /**
   *
   * @dev requestRandomWords: request 1 to n uint256 integers
   * requestRandomWords is overloaded. In this instance you can
   * call it without explicitly declaring a refund address, with the
   * refund being paid to the tx.origin for this call.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestRandomWords(
    uint256 numberOfNumbers_
  ) external payable returns (uint256 uniqueID_) {
    return requestRandomWords(numberOfNumbers_, tx.origin);
  }

  /**
   *
   * @dev requestRandomWords: request 1 to n uint256 integers
   * requestRandomWords is overloaded. In this instance you must
   * specify the refund address for unused native token.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   * @param refundAddress_: the address for refund of native token
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestRandomWords(
    uint256 numberOfNumbers_,
    address refundAddress_
  ) public payable returns (uint256 uniqueID_) {
    return requestWithMethod(numberOfNumbers_, 0, 0, refundAddress_, 0);
  }

  /**
   *
   * @dev requestRandomNumbersInRange: request 1 to n integers within
   * a given range (e.g. 1 to 10,000)
   * requestRandomNumbersInRange is overloaded. In this instance you can
   * call it without explicitly declaring a refund address, with the
   * refund being paid to the tx.origin for this call.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   * @param minValue_: the min of the range
   * @param maxValue_: the max of the range
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestRandomNumbersInRange(
    uint256 numberOfNumbers_,
    uint256 minValue_,
    uint256 maxValue_
  ) public payable returns (uint256 uniqueID_) {
    return
      requestRandomNumbersInRange(
        numberOfNumbers_,
        minValue_,
        maxValue_,
        tx.origin
      );
  }

  /**
   *
   * @dev requestRandomNumbersInRange: request 1 to n integers within
   * a given range (e.g. 1 to 10,000)
   * requestRandomNumbersInRange is overloaded. In this instance you must
   * specify the refund address for unused native token.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   * @param minValue_: the min of the range
   * @param maxValue_: the max of the range
   * @param refundAddress_: the address for refund of native token
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestRandomNumbersInRange(
    uint256 numberOfNumbers_,
    uint256 minValue_,
    uint256 maxValue_,
    address refundAddress_
  ) public payable returns (uint256 uniqueID_) {
    return
      requestWithMethod(
        numberOfNumbers_,
        minValue_,
        maxValue_,
        refundAddress_,
        1
      );
  }

  /**
   *
   * @dev requestWithMethod: public method to allow calls specifying the
   * arrng method, allowing functionality to be extensible without
   * requiring a new controller contract.
   * requestWithMethod is overloaded. In this instance you can
   * call it without explicitly declaring a refund address, with the
   * refund being paid to the tx.origin for this call.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   * @param minValue_: the min of the range
   * @param maxValue_: the max of the range
   * @param method_: the arrng method to call
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestWithMethod(
    uint256 numberOfNumbers_,
    uint256 minValue_,
    uint256 maxValue_,
    uint32 method_
  ) public payable returns (uint256 uniqueID_) {
    return
      requestWithMethod(
        numberOfNumbers_,
        minValue_,
        maxValue_,
        tx.origin,
        method_
      );
  }

  /**
   *
   * @dev requestWithMethod: public method to allow calls specifying the
   * arrng method, allowing functionality to be extensible without
   * requiring a new controller contract.
   * requestWithMethod is overloaded. In this instance you must
   * specify the refund address for unused native token.
   *
   * @param numberOfNumbers_: the amount of numbers to request
   * @param minValue_: the min of the range
   * @param maxValue_: the max of the range
   * @param refundAddress_: the address for refund of native token
   * @param method_: the arrng method to call
   *
   * @return uniqueID_ : unique ID for this request
   */
  function requestWithMethod(
    uint256 numberOfNumbers_,
    uint256 minValue_,
    uint256 maxValue_,
    address refundAddress_,
    uint32 method_
  ) public payable returns (uint256 uniqueID_) {
    return
      _requestRandomness(
        msg.sender,
        msg.value,
        method_,
        numberOfNumbers_,
        minValue_,
        maxValue_,
        refundAddress_
      );
  }

  /**
   *
   * @dev _requestRandomness: request RNG
   *
   * @param caller_: the msg.sender that has made this call
   * @param payment_: the msg.value sent with the call
   * @param method_: the method for the oracle to execute
   * @param numberOfNumbers_: the amount of numbers to request
   * @param minValue_: the min of the range
   * @param maxValue_: the max of the range
   * @param refundAddress_: the address for refund of ununsed native token
   *
   * @return uniqueID_ : unique ID for this request
   */
  function _requestRandomness(
    address caller_,
    uint256 payment_,
    uint256 method_,
    uint256 numberOfNumbers_,
    uint256 minValue_,
    uint256 maxValue_,
    address refundAddress_
  ) internal returns (uint256 uniqueID_) {
    // With 18,446,744,073,709,551,615 possible requests, overflows are not feasible,
    // and therefore not worth the additional gas overhead to protect against
    unchecked {
      arrngRequestId += 1;
    }

    if (payment_ < minimumNativeToken) {
      string memory message = string.concat(
        "Insufficient native token for gas, minimum is ",
        minimumNativeToken.toString(),
        ". You may need more depending on the number of numbers requested and prevailing gas cost. All excess refunded, less txn fee."
      );
      require(payment_ >= minimumNativeToken, message);
    }

    require(numberOfNumbers_ > 0, "Must request more than 0 numbers");

    require(
      numberOfNumbers_ <= maximumNumberOfNumbers,
      "Request exceeds maximum number of numbers"
    );

    _processPayment(oracleAddress, payment_);

    emit ArrngRequest(
      caller_,
      uint64(arrngRequestId),
      uint32(method_),
      uint64(numberOfNumbers_),
      uint64(minValue_),
      uint64(maxValue_),
      uint64(payment_),
      refundAddress_
    );

    return (arrngRequestId);
  }

  /**
   *
   * @dev serveRandomness: serve result of the call
   *
   * @param arrngRequestId_: unique request ID
   * @param callingAddress_: the contract to call
   * @param requestTxnHash_: the txn hash of the original request
   * @param responseCode_: 0 is success, !0 = failure
   * @param randomNumbers_: the array of random integers
   * @param refundAddress_: the address for refund of native token not used for gas
   * @param apiResponse_: the response from the off-chain rng provider
   * @param apiSignature_: signature for the rng response
   * @param feeCharged_: the fee for this rng
   *
   */
  function serveRandomness(
    uint256 arrngRequestId_,
    address callingAddress_,
    bytes32 requestTxnHash_,
    uint256 responseCode_,
    uint256[] calldata randomNumbers_,
    address refundAddress_,
    string calldata apiResponse_,
    string calldata apiSignature_,
    uint256 feeCharged_
  ) external payable {
    require(msg.sender == oracleAddress, "Oracle address only");

    emit ArrngResponse(requestTxnHash_);

    if (responseCode_ == 0) {
      _arrngSuccess(
        arrngRequestId_,
        callingAddress_,
        randomNumbers_,
        refundAddress_,
        apiResponse_,
        apiSignature_,
        msg.value,
        feeCharged_
      );
    } else {
      _arrngFailure(
        arrngRequestId_,
        callingAddress_,
        refundAddress_,
        msg.value
      );
    }
  }

  /**
   *
   * @dev _arrngSuccess: process a successful response
   * arrng can be requested by a contract call or from an EOA. In the
   * case of a contract call we call the external method that the calling
   * contract must include to perform downstream processing using the rng. In
   * the case of an EOA call this is a user requesting signed, verifiable rng
   * that is stored on-chain (through emitted events), that they intend to use
   * manually. So in the case of the EOA call we emit the results and send them
   * the refund, i.e. no method call.
   *
   * @param arrngRequestId_: unique request ID
   * @param callingAddress_: the contract to call
   * @param randomNumbers_: the array of random integers
   * @param refundAddress_: the address for unused token refund
   * @param apiResponse_: the response from the off-chain rng provider
   * @param apiSignature_: signature for the rng response
   * @param refundAmount_: the amount of unused native toke to refund
   * @param feeCharged_: the fee for this rng
   *
   */
  function _arrngSuccess(
    uint256 arrngRequestId_,
    address callingAddress_,
    uint256[] calldata randomNumbers_,
    address refundAddress_,
    string calldata apiResponse_,
    string calldata apiSignature_,
    uint256 refundAmount_,
    uint256 feeCharged_
  ) internal {
    // Success
    emit ArrngServed(
      uint128(arrngRequestId_),
      uint128(feeCharged_),
      randomNumbers_,
      apiResponse_,
      apiSignature_
    );

    if (callingAddress_.code.length > 0) {
      // If the calling contract is the same as the refund address then return
      // ramdomness and the refund in a single function call:
      if (refundAddress_ == callingAddress_) {
        IArrngConsumer(callingAddress_).receiveRandomness{value: refundAmount_}(
          arrngRequestId_,
          randomNumbers_
        );
      } else {
        IArrngConsumer(callingAddress_).receiveRandomness{value: 0}(
          arrngRequestId_,
          randomNumbers_
        );
        _processPayment(refundAddress_, refundAmount_);
      }
    } else {
      // Refund the EOA any native token not used for gas:
      _processPayment(refundAddress_, refundAmount_);
    }
  }

  /**
   *
   * @dev _arrngFailure: process a failed response
   * Refund any native token not used for gas:
   *
   * @param arrngRequestId_: unique request ID
   * @param callingAddress_: the contract to call
   * @param refundAddress_: the address for the refund
   * @param amount_: the amount for the refund
   *
   */
  function _arrngFailure(
    uint256 arrngRequestId_,
    address callingAddress_,
    address refundAddress_,
    uint256 amount_
  ) internal {
    // Failure
    emit ArrngRefundInsufficientTokenForGas(callingAddress_, arrngRequestId_);
    _processPayment(refundAddress_, amount_);
  }

  /**
   *
   * @dev _processPayment: central function for payment processing
   *
   * @param payeeAddress_: address to pay.
   * @param amount_: amount to pay.
   *
   */
  function _processPayment(address payeeAddress_, uint256 amount_) internal {
    (bool success, ) = payeeAddress_.call{value: amount_}("");
    require(success, "TheTransferWalkedThePlank!(failed)");
  }
}

