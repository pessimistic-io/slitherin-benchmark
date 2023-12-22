// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Import the required libraries and contracts
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol";
import "./IERC20Metadata.sol";

import "./IEntryPoint.sol";
import "./BasePaymaster.sol";
import "./UniswapHelper.sol";
import "./OracleHelper.sol";
import "./IOracle.sol";

struct PaymasterParams {
  address signer;
  IEntryPoint entryPoint;
  IERC20Metadata wrappedNative;
  ISwapRouter uniswap;
  IOracle nativeOracle;
  address treasury;
}

struct PaymasterAndData {
  address paymaster;
  IERC20Metadata token;
  bool postTransfer;
  bool userCheck;
  uint48 validUntil;
  uint48 validAfter;
  uint256 preCharge;
  uint256 preFee;
  uint256 userBalance;
}

contract Paymaster is BasePaymaster, UniswapHelper, OracleHelper, ReentrancyGuard {
  using ECDSA for bytes32;
  using UserOperationLib for UserOperation;
  using SafeERC20 for IERC20Metadata;

  enum TokenStatus {
    ADDED,
    REMOVED
  }

  struct TokenPaymasterConfig {
    /// @notice The price markup percentage applied to the token price (1e6 = 100%)
    uint256 priceMarkup;
    /// @notice Estimated gas cost for refunding tokens after the transaction is completed
    uint256 refundPostopCost;
    /// @notice Transactions are only valid as long as the cached price is not older than this value
    uint256 priceMaxAge;
    /// @notice The Oracle contract used to fetch the latest Token prices
    IOracle oracle;
    bool toNative;
  }

  /// @notice The fee percentage (1e6 = 100%)
  uint256 private constant FEE = 300;

  /// @notice All 'price' variables are multiplied by this value to avoid rounding up
  uint256 private constant PRICE_DENOMINATOR = 1e26;

  uint256 private constant FEE_DENOMINATOR = 1e6;

  uint256 private constant TOKEN_OFFSET = 20;

  uint256 private constant VALID_TIMESTAMP_OFFSET = 40;

  uint256 private constant SIGNATURE_OFFSET = 264;

  IOracle private constant NULL_ORACLE = IOracle(address(0));

  address public verifyingSigner;
  address public treasury;

  IERC20Metadata[] public tokenList;

  mapping(IERC20Metadata => TokenPaymasterConfig) public configs;

  /// @notice The balance (in token/eth) represent the debts or the remaining of the balance
  mapping(IERC20Metadata => mapping(address => int256)) public balances;

  event PostOpReverted(address indexed user, uint256 preCharge, uint256 actualGasCost, int256 debt, uint256 fee, uint256 actualChargeNative);

  event Pay(address indexed user, IERC20Metadata token, uint256 actualTokenCharge, uint256 fee);

  event Token(IERC20Metadata indexed token, TokenStatus status);

  event Debug1(uint256 cachedPriceWithMarkup, uint256 actualTokenNeeded, uint256 preCharge, uint256 preFee, bool postTrasfer);
  event Debug2(uint256 allowance);
  event Debug3(uint256 cachedPriceWithMarkup, uint256 actualTokenNeeded, uint256 preCharge, uint256 preFee, bool postTrasfer);

  /// @notice Initializes the Paymaster contract with the given parameters.
  constructor(
    PaymasterParams memory params
  )
    BasePaymaster(params.entryPoint)
    UniswapHelper(params.wrappedNative, params.uniswap)
    OracleHelper(params.nativeOracle)
  {
    verifyingSigner = params.signer;
    treasury = params.treasury;
  }

  function setVerifyingSigner(address _verifyingSigner) external onlyOwner {
    verifyingSigner = _verifyingSigner;
  }

  function setTresury(address _treasury) external {
    require(treasury == msg.sender, "Invalid sender");

    for (uint16 i = 0; i < tokenList.length; i++) {
      IERC20Metadata token = tokenList[i];
      int256 tmpBalance = balances[token][treasury];

      if (tmpBalance > 0) {
        balances[token][treasury] = 0;
        balances[token][_treasury] = tmpBalance;
      }
    }

    treasury = _treasury;
  }

  /// @notice Allows the contract owner to add a new tokens.
  /// @param tokens The token to deposit.
  function addTokens(
    IERC20Metadata[] calldata tokens,
    TokenPaymasterConfig[] calldata tokenPaymasterConfigs
  ) external onlyOwner {
    require(tokens.length == tokenPaymasterConfigs.length, "Invalid tokens and configs length");

    for (uint i = 0; i < tokens.length; i++) {
      IOracle oracle = configs[tokens[i]].oracle;
      if (oracle != NULL_ORACLE) continue;

      IERC20Metadata token = tokens[i];
      TokenPaymasterConfig memory config = tokenPaymasterConfigs[i];

      if (config.oracle == NULL_ORACLE) continue;
      if (config.priceMarkup <= 2 * PRICE_DENOMINATOR && config.priceMarkup >= PRICE_DENOMINATOR) {
        configs[token] = config;
        tokenList.push(token);

        emit Token(token, TokenStatus.ADDED);
      }
    }
  }

  /// @notice Allows the contract owner to delete the token.
  /// @param tokens The tokens to be removed.
  function removeTokens(IERC20Metadata[] calldata tokens) external onlyOwner {
    for (uint i = 0; i < tokens.length; i++) {
      IERC20Metadata token = tokens[i];
      int tokenIndex = _tokenIndex(token);

      if (tokenIndex >= 0 && configs[token].oracle != NULL_ORACLE) {
        tokenList[uint256(tokenIndex)] = tokenList[tokenList.length - 1];

        delete configs[token];
        tokenList.pop();
        emit Token(token, TokenStatus.REMOVED);
      }
    }
  }

  /// @notice Allows the user to withdraw a specified amount of tokens from the contract.
  /// @param token The token to withdraw.
  /// @param amount The amount of tokens to transfer.
  function withdrawToken(IERC20Metadata token, uint256 amount) external nonReentrant {
    require(address(token) != address(0), "Invalid token contract");

    int256 balance = balances[token][msg.sender];

    require(int(amount) <= balance, "Insufficient balance");

    balances[token][msg.sender] = balance - int(amount);

    token.transfer(msg.sender, amount);
  }

  function depositToken(IERC20Metadata token, uint256 amount, address to) external payable nonReentrant {
    require(address(token) != address(0), "Invalid token contract");

    int256 balance = balances[token][to];
    int256 debts = type(int256).max;

    if (balance < 0) {
      debts = -balance;
    }

    if (int(amount) > debts) {
      balances[token][owner()] += debts;
    } else if (int(amount) < debts) {
      balances[token][owner()] += int(amount);
    }

    balances[token][to] = balance + int(amount);

    token.transferFrom(msg.sender, address(this), amount);
  }

  /// @notice Allows the contract owner to refill entry point deposit with a specified amount of tokens
  function refillEntryPointDeposit(IERC20Metadata token, uint256 amount) external canSwap onlyOwner {
    require(address(token) != address(0), "Invalid token contract");

    int256 balance = balances[token][owner()];

    require(amount <= uint256(balance), "Insufficient balance");

    balances[token][owner()] = balance - int256(amount);

    TokenPaymasterConfig memory config = configs[token];
    IOracle oracle = config.oracle;
    uint256 swappedWNative = amount;

    if (token != wrappedNative) {
      require(oracle != NULL_ORACLE, "Unsupported token");

      uint256 cachedPrice = _updateCachedPrice(token, oracle, config.toNative, false);
      swappedWNative = _maybeSwapTokenToWNative(token, amount, cachedPrice);
    }

    unwrapWeth(swappedWNative);

    entryPoint.depositTo{ value: address(this).balance }(address(this));
  }

  function updateTokenPrice(IERC20Metadata token) external {
    TokenPaymasterConfig memory config = configs[token];
    require(config.oracle != NULL_ORACLE, "Invalid oracle address");
    _updateCachedPrice(token, config.oracle, config.toNative, true);
  }

  receive() external payable {}

  /// @notice Validates a paymaster user operation and calculates the required token amount for the transaction.
  /// @param userOp The user operation data.
  /// @param requiredPreFund The amount of tokens required for pre-funding.
  /// @return context The context containing the token amount and user sender address (if applicable).
  /// @return validationResult A uint256 value indicating the result of the validation (always 0 in this implementation).
  function _validatePaymasterUserOp(
    UserOperation calldata userOp,
    bytes32,
    uint256 requiredPreFund
  ) internal override returns (bytes memory context, uint256 validationResult) {
    (bool verified, PaymasterAndData memory paymasterAndData) = _verifySignature(userOp);

    IERC20Metadata token = paymasterAndData.token;

    require(address(token) != address(0), "Invalid token address");

    TokenPaymasterConfig memory config = configs[token];

    require(config.oracle != NULL_ORACLE, "Invalid oracle address");
    require(balances[token][userOp.sender] >= 0, "Still have debts");

    uint48 validUntil = paymasterAndData.validUntil;
    uint48 validAfter = paymasterAndData.validAfter;

    if (!verified) {
      return ("", _packValidationData(true, validUntil, validAfter));
    }

    // Could be in eth or token
    uint256 preCharge = paymasterAndData.preCharge;
    uint256 preFee = paymasterAndData.preFee;
    uint256 totalPreCharge = preCharge + preFee;

    if (paymasterAndData.preCharge <= 0) {
      uint256 preChargeNative = requiredPreFund + (config.refundPostopCost * userOp.maxFeePerGas);

      if (token != wrappedNative) {
        uint256 cachedPriceWithMarkup = _cachedPriceWithMarkup(token, config);

        preCharge = weiToToken(token, preChargeNative, cachedPriceWithMarkup);
        preFee = (preCharge * FEE) / FEE_DENOMINATOR;
        totalPreCharge = preCharge + preFee;
        validUntil = uint48(getCachedPriceTimestamp(token) + config.priceMaxAge);
        validAfter = 0;
      }
    }

    validationResult = _packValidationData(false, validUntil, validAfter);
    context = abi.encode(
      token,
      paymasterAndData.postTransfer,
      preCharge,
      preFee,
      totalPreCharge,
      userOp.maxFeePerGas,
      userOp.maxPriorityFeePerGas,
      config.refundPostopCost,
      userOp.sender
    );

    // Charge the user/sender on postOp()
    if (paymasterAndData.postTransfer) {
      uint256 balance = paymasterAndData.userCheck ? token.balanceOf(userOp.sender) : paymasterAndData.userBalance;
      require(balance >= totalPreCharge, "Insufficient balance");

      return (context, validationResult);
    }

    token.safeTransferFrom(userOp.sender, address(this), totalPreCharge);

    balances[token][treasury] += int256(preFee);
  }

  /// @notice Performs post-operation tasks, such as updating the token price and refunding excess tokens.
  /// @dev This function is called after a user operation has been executed or reverted.
  /// @param mode The post-operation mode (either successful or reverted).
  /// @param context The context containing the token amount and user sender address.
  /// @param actualGasCost The actual gas cost of the transaction.
  function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
    (
      address tokenAddress,
      bool postTransfer,
      uint256 preCharge,
      uint256 preFee,
      uint256 totalPreCharge,
      uint256 maxFeePerGas,
      uint256 maxPriorityFeePerGas,
      uint256 refundPostopCost,
      address userOpSender
    ) = abi.decode(context, (address, bool, uint256, uint256, uint256, uint256, uint256, uint256, address));

    IERC20Metadata token = IERC20Metadata(tokenAddress);
    uint256 gasPrice = _gasPrice(maxFeePerGas, maxPriorityFeePerGas);
    uint256 actualChargeNative = actualGasCost + (refundPostopCost * gasPrice);

    if (mode == PostOpMode.postOpReverted) {
      int256 debt = _tokenDebt(token, postTransfer, preCharge, actualChargeNative, preFee);
      balances[token][userOpSender] -= debt;

      emit PostOpReverted(userOpSender, totalPreCharge, actualGasCost, debt, preFee, actualChargeNative);
    } else {
      _payWithToken(token, userOpSender, postTransfer, preCharge, preFee, actualChargeNative);
    }
  }

  function _verifySignature(
    UserOperation calldata userOp
  ) internal view returns (bool verified, PaymasterAndData memory data) {
    require(userOp.paymasterAndData.length >= SIGNATURE_OFFSET, "Invalid paymaster and data length");

    (PaymasterAndData memory paymasterAndData, bytes calldata signature) = _parsePaymasterAndData(
      userOp.paymasterAndData
    );

    require(signature.length == 64 || signature.length == 65, "Invalid signature length in paymasterAndData");

    bytes32 hash = ECDSA.toEthSignedMessageHash(_hash(userOp, paymasterAndData));

    verified = verifyingSigner == ECDSA.recover(hash, signature);
    data = paymasterAndData;
  }

  function _parsePaymasterAndData(
    bytes calldata data
  ) internal pure returns (PaymasterAndData memory paymasterAndData, bytes calldata signature) {
    address paymaster = address(bytes20(data[:TOKEN_OFFSET]));
    IERC20Metadata token = IERC20Metadata(address(bytes20(data[TOKEN_OFFSET:VALID_TIMESTAMP_OFFSET])));

    (
      bool postTransfer,
      bool userCheck,
      uint48 validUntil,
      uint48 validAfter,
      uint256 preCharge,
      uint256 preFee,
      uint256 userBalance
    ) = abi.decode(
        data[VALID_TIMESTAMP_OFFSET:SIGNATURE_OFFSET],
        (bool, bool, uint48, uint48, uint256, uint256, uint256)
      );

    signature = data[SIGNATURE_OFFSET:];
    paymasterAndData = PaymasterAndData(
      paymaster,
      token,
      postTransfer,
      userCheck,
      validUntil,
      validAfter,
      preCharge,
      preFee,
      userBalance
    );
  }

  function _hash(
    UserOperation calldata userOp,
    PaymasterAndData memory paymasterAndData
  ) internal view returns (bytes32) {
    address sender = userOp.getSender();

    return
      keccak256(
        abi.encode(
          sender,
          userOp.nonce,
          keccak256(userOp.initCode),
          keccak256(userOp.callData),
          userOp.callGasLimit,
          userOp.verificationGasLimit,
          userOp.preVerificationGas,
          userOp.maxFeePerGas,
          userOp.maxPriorityFeePerGas,
          block.chainid,
          paymasterAndData.paymaster,
          paymasterAndData.token,
          paymasterAndData.postTransfer,
          paymasterAndData.validUntil,
          paymasterAndData.validAfter,
          paymasterAndData.preCharge,
          paymasterAndData.preFee
        )
      );
  }

  function _cachedPriceWithMarkup(IERC20Metadata token, TokenPaymasterConfig memory config) internal returns (uint256) {
    uint256 cachedPrice = _updateCachedPrice(token, config.oracle, config.toNative, false);
    return (cachedPrice * PRICE_DENOMINATOR) / config.priceMarkup;
  }

  function _gasPrice(uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) internal view returns (uint256) {
    if (maxFeePerGas == maxPriorityFeePerGas) {
      //legacy mode (for networks that don't support basefee opcode)
      return maxFeePerGas;
    }
    return _min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
  }

  function _min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }

  function _payWithToken(
    IERC20Metadata token,
    address sender,
    bool postTransfer,
    uint256 preCharge,
    uint256 preFee,
    uint256 actualGas
  ) internal {
    int256 balance = balances[token][sender];

    require(balance >= 0, "Still have debts");

    TokenPaymasterConfig memory config = configs[token];

    uint256 cachedPriceWithMarkup = _cachedPriceWithMarkup(token, config);
    uint256 actualTokenNeeded = weiToToken(token, actualGas, cachedPriceWithMarkup);

    emit Debug1(cachedPriceWithMarkup, actualTokenNeeded, preCharge, preFee, postTransfer);

    uint256 allowance = token.allowance(sender, address(this));

    emit Debug2(allowance);

    if (postTransfer) {
      token.safeTransferFrom(sender, address(this), actualTokenNeeded + preFee);
      balances[token][treasury] += int256(preFee);
    } else {
      if (preCharge > actualTokenNeeded) {
        balances[token][sender] += int256(preCharge - actualTokenNeeded);
      } else if (actualTokenNeeded > preCharge) {
        token.safeTransferFrom(sender, address(this), actualTokenNeeded - preCharge);
      }
    }

    emit Pay(sender, token, actualTokenNeeded, preFee);

    balances[token][owner()] += int256(actualTokenNeeded);
  }

  function _tokenDebt(
    IERC20Metadata token,
    bool postTransfer,
    uint256 preCharge,
    uint256 actualGas,
    uint256 preFee
  ) internal returns (int256 debts) {
    TokenPaymasterConfig memory config = configs[token];

    uint256 cachedPriceWithMarkup = _cachedPriceWithMarkup(token, config);
    uint256 actualTokenNeeded = weiToToken(token, actualGas, cachedPriceWithMarkup);

    emit Debug3(cachedPriceWithMarkup, actualTokenNeeded, preCharge, preFee, postTransfer);

    if (postTransfer) {
      debts = int256(actualTokenNeeded + preFee);
    } else {
      if (actualTokenNeeded > preCharge) {
        debts = int256(actualTokenNeeded - preCharge);
      }
    }
  }

  function _tokenIndex(IERC20Metadata token) internal view returns (int index) {
    index = -1;

    IERC20Metadata[] memory _tokenList = tokenList;

    for (uint i; i < _tokenList.length; i++) {
      if (_tokenList[i] == token) {
        return int(i);
      }
    }
  }
}

