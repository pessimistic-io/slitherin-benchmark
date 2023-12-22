// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;


/**
 *    ,,                           ,,                                
 *   *MM                           db                      `7MM      
 *    MM                                                     MM      
 *    MM,dMMb.      `7Mb,od8     `7MM      `7MMpMMMb.        MM  ,MP'
 *    MM    `Mb       MM' "'       MM        MM    MM        MM ;Y   
 *    MM     M8       MM           MM        MM    MM        MM;Mm   
 *    MM.   ,M9       MM           MM        MM    MM        MM `Mb. 
 *    P^YbmdP'      .JMML.       .JMML.    .JMML  JMML.    .JMML. YA.
 *
 *    Primitives01.sol :: 0x79f147176824196789f07dfc2d21e100ee1ae138
 *    etherscan.io verified 2023-11-30
 */ 
import "./Math.sol";
import "./SignedMath.sol";
import "./StrategyBase.sol";
import "./ICallExecutor.sol";
import "./IUint256Oracle.sol";
import "./IPriceCurve.sol";
import "./Bit.sol";
import "./TokenHelper.sol";
import "./SwapIO.sol";

error NftIdAlreadyOwned();
error NotEnoughNftReceived();
error NotEnoughTokenReceived(uint amountReceived);
error MerkleProofAndAmountMismatch();
error BlockMined();
error BlockNotMined();
error OracleUint256ReadZero();
error Uint256LowerBoundNotMet(uint256 oraclePrice);
error Uint256UpperBoundNotMet(uint256 oraclePrice);
error InvalidTokenInIds();
error InvalidTokenOutIds();
error BitUsed();
error BitNotUsed();
error SwapIdsAreEqual();
error InvalidSwapIdsLength();
error MaxBlockIntervals();
error BlockIntervalTooShort();

struct UnsignedTransferData {
  address recipient;
  IdsProof idsProof;
}

struct UnsignedMarketSwapData {
  address recipient;
  IdsProof tokenInIdsProof;
  IdsProof tokenOutIdsProof;
  Call fillCall;
}

struct UnsignedLimitSwapData {
  address recipient;
  uint amount;
  IdsProof tokenInIdsProof;
  IdsProof tokenOutIdsProof;
  Call fillCall;
}

struct UnsignedStakeProofData {
  bytes stakerSignature;
}

contract Primitives01 is TokenHelper, StrategyBase, SwapIO {
  using Math for uint256;
  using SignedMath for int256;

  ICallExecutor constant CALL_EXECUTOR_V2 = ICallExecutor(0x6FE756B9C61CF7e9f11D96740B096e51B64eBf13);

  // require bitmapIndex/bit not to be used
  function requireBitNotUsed (uint bitmapIndex, uint bit) public {
    uint256 bitmap = Bit.loadUint(Bit.bitmapPtr(bitmapIndex));
    if (bitmap & bit != 0) {
      revert BitUsed();
    }
  }

  // require bitmapIndex/bit to be used
  function requireBitUsed (uint bitmapIndex, uint bit) public {
    uint256 bitmap = Bit.loadUint(Bit.bitmapPtr(bitmapIndex));
    if (bitmap & bit == 0) {
      revert BitNotUsed();
    }
  }

  // set bitmapIndex/bit to used. Requires bit not to be used
  function useBit (uint bitmapIndex, uint bit) public {
    Bit.useBit(bitmapIndex, bit);
  }

  // require block <= current block
  function requireBlockMined (uint blockNumber) public view {
    if (blockNumber > block.number) {
      revert BlockNotMined();
    }
  }

  function requireBlockNotMined (uint blockNumber) public view {
    if (blockNumber <= block.number) {
      revert BlockMined();
    }
  }

  /**
    * @dev Allow execution on a block interval
    * @param id A unique id for the block interval. This id is used to store the block interval state. Use a random id to avoid collisions.
    * @param initialStart The initial start block number. Setting this to 0 will allow the first execution to occur immediately.
    * @param intervalMinSize The minimum size of the block interval. This is a minimum because the actual interval can be longer if execution is delayed.
    * @param maxIntervals The maximum number of intervals that can be executed. Set this to 0 for unlimited executions.
    */
  function blockInterval (uint64 id, uint128 initialStart, uint128 intervalMinSize, uint16 maxIntervals) public {
    (uint128 start, uint16 counter) = getBlockIntervalState(id);
    if (start == 0) {
      start = initialStart;
    }

    if (maxIntervals > 0 && counter >= maxIntervals) {
      revert MaxBlockIntervals();
    }

    uint128 blockNum = uint128(block.number);

    if (blockNum < start + intervalMinSize) {
      revert BlockIntervalTooShort();
    }

    _setBlockIntervalState(id, blockNum, counter + 1);
  }

  // Require a lower bound uint256 returned from an oracle. Revert if oracle returns 0.
  function requireUint256LowerBound (IUint256Oracle uint256Oracle, bytes memory params, uint lowerBound) public view {
    uint256 oracleUint256 = uint256Oracle.getUint256(params);
    if (oracleUint256 == 0) {
      revert OracleUint256ReadZero();
    }
    if(oracleUint256 > lowerBound) {
      revert Uint256LowerBoundNotMet(oracleUint256);
    }
  }

  // Require an upper bound uint256 returned from an oracle
  function requireUint256UpperBound (IUint256Oracle uint256Oracle, bytes memory params, uint upperBound) public {
    uint256 oracleUint256 = uint256Oracle.getUint256(params);
    if(oracleUint256 < upperBound) {
      revert Uint256UpperBoundNotMet(oracleUint256);
    }
  }

  function transfer (
    Token memory token,
    address owner,
    address recipient,
    uint amount,
    UnsignedTransferData memory data
  ) public {
    revert("NOT IMPLEMENTED");
  }

  // given an exact tokenIn amount, fill a tokenIn -> tokenOut swap at market price, as determined by priceOracle
  function marketSwapExactInput (
    IUint256Oracle priceOracle,
    bytes memory priceOracleParams,
    address owner,
    Token memory tokenIn,
    Token memory tokenOut,
    uint tokenInAmount,
    uint24 feePercent,
    uint feeMinTokenOut,
    UnsignedMarketSwapData memory data
  ) public {
    uint tokenOutAmount = getSwapAmount(priceOracle, priceOracleParams, tokenInAmount);
    tokenOutAmount = tokenOutAmount - calcFee(tokenOutAmount, feePercent, feeMinTokenOut);
    _fillSwap(
      tokenIn,
      tokenOut,
      owner,
      data.recipient,
      tokenInAmount,
      tokenOutAmount,
      data.tokenInIdsProof,
      data.tokenOutIdsProof,
      data.fillCall
    );
  }

  // given an exact tokenOut amount, fill a tokenIn -> tokenOut swap at market price, as determined by priceOracle
  function marketSwapExactOutput (
    IUint256Oracle priceOracle,
    bytes memory priceOracleParams,
    address owner,
    Token memory tokenIn,
    Token memory tokenOut,
    uint tokenOutAmount,
    uint24 feePercent,
    uint feeMinTokenIn,
    UnsignedMarketSwapData memory data
  ) public {
    uint tokenInAmount = getSwapAmount(priceOracle, priceOracleParams, tokenOutAmount);
    tokenInAmount = tokenInAmount + calcFee(tokenInAmount, feePercent, feeMinTokenIn);
    _fillSwap(
      tokenIn,
      tokenOut,
      owner,
      data.recipient,
      tokenInAmount,
      tokenOutAmount,
      data.tokenInIdsProof,
      data.tokenOutIdsProof,
      data.fillCall
    );
  }

  // fill all or part of a swap for tokenIn -> tokenOut, with exact tokenInAmount.
  // Price curve calculates output based on input
  function limitSwapExactInput (
    address owner,
    Token memory tokenIn,
    Token memory tokenOut,
    uint tokenInAmount,
    IPriceCurve priceCurve,
    bytes memory priceCurveParams,
    FillStateParams memory fillStateParams,
    UnsignedLimitSwapData memory data
  ) public {
    int fillStateX96 = getFillStateX96(fillStateParams.id);
    uint filledInput = getFilledAmount(fillStateParams, fillStateX96, tokenInAmount);

    uint tokenOutAmountRequired = limitSwapExactInput_getOutput(
      data.amount,
      filledInput,
      tokenInAmount,
      priceCurve,
      priceCurveParams
    );

    _setFilledAmount(fillStateParams, filledInput + data.amount, tokenInAmount);

    _fillSwap(
      tokenIn,
      tokenOut,
      owner,
      data.recipient,
      data.amount,
      tokenOutAmountRequired,
      data.tokenInIdsProof,
      data.tokenOutIdsProof,
      data.fillCall
    );
  }

  // fill all or part of a swap for tokenIn -> tokenOut, with exact tokenOutAmount.
  // Price curve calculates input based on output
  function limitSwapExactOutput (
    address owner,
    Token memory tokenIn,
    Token memory tokenOut,
    uint tokenOutAmount,
    IPriceCurve priceCurve,
    bytes memory priceCurveParams,
    FillStateParams memory fillStateParams,
    UnsignedLimitSwapData memory data
  ) public {
    int fillStateX96 = getFillStateX96(fillStateParams.id);
    uint filledOutput = getFilledAmount(fillStateParams, fillStateX96, tokenOutAmount);

    uint tokenInAmountRequired = limitSwapExactOutput_getInput(
      data.amount,
      filledOutput,
      tokenOutAmount,
      priceCurve,
      priceCurveParams
    );

    _setFilledAmount(fillStateParams, filledOutput + data.amount, tokenOutAmount);

    _fillSwap(
      tokenIn,
      tokenOut,
      owner,
      data.recipient,
      tokenInAmountRequired,
      data.amount,
      data.tokenInIdsProof,
      data.tokenOutIdsProof,
      data.fillCall
    );
  }
  

  function _checkUnsignedTransferData (Token memory token, uint amount, UnsignedTransferData memory unsignedData) private pure {
    if (token.idsMerkleRoot != bytes32(0) && unsignedData.idsProof.ids.length != amount) {
      revert MerkleProofAndAmountMismatch();
    }
  }

  function _fillSwap (
    Token memory tokenIn,
    Token memory tokenOut,
    address owner,
    address recipient,
    uint tokenInAmount,
    uint tokenOutAmount,
    IdsProof memory tokenInIdsProof,
    IdsProof memory tokenOutIdsProof,
    Call memory fillCall
  ) internal {
    verifyTokenIds(tokenIn, tokenInIdsProof);
    verifyTokenIds(tokenOut, tokenOutIdsProof);

    transferFrom(tokenIn.addr, tokenIn.standard, owner, recipient, tokenInAmount, tokenInIdsProof.ids);

    uint initialTokenOutBalance;
    {
      (uint _initialTokenOutBalance, uint initialOwnedIdCount,) = tokenOwnership(owner, tokenOut.standard, tokenOut.addr, tokenOutIdsProof.ids);
      initialTokenOutBalance = _initialTokenOutBalance;
      if (tokenOut.standard == TokenStandard.ERC721 && initialOwnedIdCount != 0) {
        revert NftIdAlreadyOwned();
      }
    }

    CALL_EXECUTOR_V2.proxyCall(fillCall.targetContract, fillCall.data);

    (uint finalTokenOutBalance,,) = tokenOwnership(owner, tokenOut.standard, tokenOut.addr, tokenOutIdsProof.ids);

    uint256 tokenOutAmountReceived = finalTokenOutBalance - initialTokenOutBalance;
    if (tokenOutAmountReceived < tokenOutAmount) {
      revert NotEnoughTokenReceived(tokenOutAmountReceived);
    }
  }

  function getSwapAmount (IUint256Oracle priceOracle, bytes memory priceOracleParams, uint token0Amount) public view returns (uint token1Amount) {
    uint priceX96 = priceOracle.getUint256(priceOracleParams);
    token1Amount = calcSwapAmount(priceX96, token0Amount);
  }

  function getFillStateX96 (uint64 fillStateId) public view returns (int fillState) {
    bytes32 position = keccak256(abi.encode(fillStateId, "fillState"));
    assembly { fillState := sload(position) } 
  }

  function getBlockIntervalState (uint64 id) public view returns (uint128 start, uint16 counter) {
    bytes32 position = keccak256(abi.encode(id, "blockInterval"));
    bytes32 slot;
    assembly { slot := sload(position) }
    start = uint128(uint256(slot));
    counter = uint16(uint256(slot >> 128)); 
  }

  function _setFilledAmount (FillStateParams memory fillStateParams, uint filledAmount, uint totalAmount) internal {
    _setFilledPercentX96(fillStateParams, filledAmount.mulDiv(Q96, totalAmount) + 1);
  }

  function _setFilledPercentX96 (FillStateParams memory fillStateParams, uint filledPercentX96) internal {
    int8 i = fillStateParams.sign ? int8(1) : -1;
    int j = fillStateParams.sign ? int(0) : int(Q96);
    int8 k = fillStateParams.sign ? -1 : int8(1);
    _setFillState(
      fillStateParams.id,
      (i * int128(fillStateParams.startX96) + j - int(filledPercentX96)) * k
    );
  }

  function _setFillState (uint64 fillStateId, int fillState) internal {
    bytes32 position = keccak256(abi.encode(fillStateId, "fillState"));
    assembly { sstore(position, fillState) } 
  }

  function _sign (int n) internal pure returns (int8 sign) {
    return n >= 0 ? int8(1) : -1;
  }

  function _setBlockIntervalState (uint64 id, uint128 start, uint16 counter) internal {
    bytes32 position = keccak256(abi.encode(id, "blockInterval"));
    bytes32 slot = bytes32(uint256(start)) | (bytes32(uint256(counter)) << 128);
    assembly { sstore(position, slot) }
  }
}

