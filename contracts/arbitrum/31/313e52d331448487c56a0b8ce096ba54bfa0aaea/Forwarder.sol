//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./AggregatorV3Interface.sol";

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC20} from "./ERC20.sol";
import {EIP712} from "./EIP712.sol";
import {SignatureChecker} from "./SignatureChecker.sol";

interface IWrapper {
  function deposit() external payable;
  function withdraw(uint256 amount) external;
}

contract Forwarder is EIP712, Ownable {
  using SafeERC20 for ERC20;

  struct ForwardRequest {
    address from;
    address to;
    address feeToken;
    uint256 value;
    uint256 gas;
    uint256 nonce;
    uint256 validUntilTime;
    bytes data;
  }

  struct FeeTokenEntry {
    bool isAllowed;
    bool isStable;
    AggregatorV3Interface chainlinkFeed;
  }

  struct SignerEntry {
    address allowedAddress;
    uint256 validUntilTime;
  }

  event Request_Executed(address indexed from, address indexed to, address feeToken, uint256 nonce);
  event Fees_Collected(address indexed token, address indexed from, address indexed to, uint256 amount, uint256 gasUsed);

  event Signer_Set(address user, address signer, address target, uint256 validUntilTime);

  event Fee_Token_Updated(address indexed tokenAddress, address chainLinkFeed, bool isAllowed, bool isStable);
  event Payment_Address_Updated(address oldPaymentAddress, address newPaymentAddress);
  event Fee_Updated(uint256 feeNumeratorGas, uint256 feeNumeratorValue, uint256 feeDenominator, uint256 minGasUsed);

  address private paymentAddress;
  address private immutable NativeTokenAddress;

  uint256 private feeNumeratorGas = 50;
  uint256 private feeNumeratorValue = 5;
  uint256 private feeDenominator = 1000;
  uint256 private minGasUsed = 100000;

  bytes32 private constant _EIP712_TYPEHASH =
    keccak256(
      "ForwardRequest(address from,address to,address feeToken,uint256 value,uint256 gas,uint256 nonce,uint256 validUntilTime,bytes data)"
    );

  mapping(address => uint256) private nonces;

  mapping(address => mapping(address => SignerEntry)) private signerData;

  mapping(address => FeeTokenEntry) private feeTokenData;

  receive() external payable {}

  constructor(
    string memory name,
    string memory version,
    address chainlink_ETH_USDC,
    address _nativeTokenAddress,
    address _paymentAddress
  ) EIP712(name, version) {
    feeTokenData[address(0)] = FeeTokenEntry(false, false, AggregatorV3Interface(chainlink_ETH_USDC));
    NativeTokenAddress = _nativeTokenAddress;
    paymentAddress = _paymentAddress;
  }

  // _view functions_

  function getNonce(address from) public view returns (uint256) {
    return nonces[from];
  }

  function verify(ForwardRequest calldata req, bytes calldata sig) public view returns (bool) {
    _verifyNonce(req);
    _verifySignature(req, sig);
    uint256 estimatedMaxFee = estimateFeeRequest(req);
    require(req.gas > minGasUsed, "not enougt gas, check min gas");
    require(ERC20(req.feeToken).balanceOf(req.from) > estimatedMaxFee, "not enought feeToken balance");
    require(ERC20(req.feeToken).allowance(req.from, address(this)) > estimatedMaxFee, "not enought feeToken allowance");

    return true;
  }

  function getSignerData(address user, address target) public view returns (SignerEntry memory) {
    return signerData[user][target];
  }

  function getFeeSetting() public view returns (uint256, uint256, uint256, uint256) {
    return (feeNumeratorGas, feeNumeratorValue, feeDenominator, minGasUsed);
  }

  function estimateFeeRequest(ForwardRequest calldata req) public view returns (uint256) {
    return estimateFee(req.feeToken, req.value, req.gas);
  }

  function estimateFee(address tokenAddress, uint256 value, uint256 gas) public view returns (uint256) {
    uint256 ethUsed = ((gas < minGasUsed ? minGasUsed : gas) * tx.gasprice * (feeNumeratorGas + feeDenominator)) / feeDenominator + value;
    if (tokenAddress == NativeTokenAddress) return ethUsed;
    return _getTokenAmount(tokenAddress, ethUsed);
  }

  function isFeeToken(address tokenAddress) public view returns (bool) {
    return feeTokenData[tokenAddress].isAllowed || tokenAddress == NativeTokenAddress;
  }

  // _state functions_

  function execute(ForwardRequest calldata req, bytes calldata sig) public payable returns (bool success, bytes memory ret) {
    _verifySignature(req, sig);
    _verifyAndUpdateNonce(req);

    uint256 initalGas = gasleft();
    if (req.feeToken == NativeTokenAddress && req.value > 0) {
      bool successValueTransfer = ERC20(NativeTokenAddress).transferFrom(req.from, address(this), req.value);      
      require(successValueTransfer, 'Forwarder: failed to collect value');
      IWrapper(NativeTokenAddress).withdraw(req.value);
    }

    uint256 gasBefore = gasleft();
    require(gasBefore >= req.gas, "Forwarder: insufficient gas");

    uint256 valueBefore = address(this).balance;
    require(valueBefore >= req.value, "Forwarder: insufficient value");

    (success, ret) = req.to.call{gas: req.gas, value: req.value}(abi.encodePacked(req.data, req.from));
    require(success, "Forwarder: contract call failed");

    uint256 gasUsed = gasBefore - gasleft();
    uint256 valueUsed = valueBefore - address(this).balance;
    require(gasUsed <= req.gas, "Forwarder: used too much gas");
    require(valueUsed <= req.value, "Forwarder: used too much value");

    // initalGas - gasBefore => add an additinal charge for the ETH unwrap
    _collectFees(req.from, req.feeToken, req.value, gasUsed + initalGas - gasBefore, valueUsed);

    uint256 valueAfter = address(this).balance;
    if (valueAfter > 0) payable(msg.sender).transfer(valueAfter);

    emit Request_Executed(req.from, req.to, req.feeToken, req.nonce);
  }

  function executeBatch(
    ForwardRequest[] calldata reqs,
    bytes[] calldata sigs
  ) public payable returns (bool[] memory success, bytes[] memory ret) {
    require(reqs.length == sigs.length, "Forwarder: number of requests does not match number of signatures");

    uint256 n = reqs.length;
    for (uint i = 0; i < n; i++) {
      (success[i], ret[i]) = execute(reqs[i], sigs[i]);
    }
  }

  function setSigner(address signer, address target, uint256 validUntilTime) public {
    require(signer != address(0), "Can not set signer to 0");
    require(target != address(0), "Can not set target to 0");
    require(validUntilTime == 0 || validUntilTime > block.timestamp, "validUntilTime must be 0 or greater then now");
    signerData[msg.sender][target] = SignerEntry(signer, validUntilTime);

    emit Signer_Set(msg.sender, signer, target, validUntilTime);
  }

  function setSignerBatch(address signer, address[] calldata targetArray, uint256 validUntilTime) public {
    for (uint256 i = 0; i < targetArray.length; i++) {
      setSigner(signer, targetArray[i], validUntilTime);
    }
  }

  // _onlyOwner function_

  function updateFeeToken(address tokenAddress, address chainLinkFeed, bool isAllowed, bool isStable) public onlyOwner {
    require(tokenAddress != address(0), "Can not set address zero");
    chainLinkFeed = isStable ? address(0) : chainLinkFeed;
    feeTokenData[tokenAddress] = FeeTokenEntry(isAllowed, isStable, AggregatorV3Interface(chainLinkFeed));
    emit Fee_Token_Updated(tokenAddress, chainLinkFeed, isAllowed, isStable);
  }

  function updatePaymentAddress(address _paymentAddress) public onlyOwner {
    require(_paymentAddress != address(0), "Can not set to address zero");
    address oldPaymentAddress = paymentAddress;
    paymentAddress = _paymentAddress;
    emit Payment_Address_Updated(oldPaymentAddress, paymentAddress);
  }

  function updateFee(uint256 _feeNumeratorGas, uint256 _feeNumeratorValue, uint256 _feeDenominator, uint256 _minGasUsed) public onlyOwner {
    require(_feeDenominator > 0, "Fee denominator can not be zero");
    feeNumeratorGas = _feeNumeratorGas;
    feeNumeratorValue = _feeNumeratorValue;
    feeDenominator = _feeDenominator;
    minGasUsed = _minGasUsed;
    emit Fee_Updated(feeNumeratorGas, feeNumeratorValue, feeDenominator, minGasUsed);
  }

  // _internal functions_

  function _verifyNonce(ForwardRequest calldata req) internal view {
    require(nonces[req.from] == req.nonce, "Forwarder: nonce mismatch");
  }

  function _verifyAndUpdateNonce(ForwardRequest calldata req) internal {
    require(nonces[req.from]++ == req.nonce, "Forwarder: nonce mismatch");
  }

  function _verifySignature(ForwardRequest calldata req, bytes calldata signature) internal view {
    require(feeTokenData[req.feeToken].isAllowed || req.feeToken == NativeTokenAddress, "Forwarder: wrong fee token");
    require(req.validUntilTime == 0 || req.validUntilTime > block.timestamp, "Forwarder: request expired");

    // https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct
    bytes32 hash = keccak256(
      abi.encode(_EIP712_TYPEHASH, req.from, req.to, req.feeToken, req.value, req.gas, req.nonce, req.validUntilTime, keccak256(req.data))
    );
    bytes32 digest = _hashTypedDataV4(hash);

    // if user signed himself => short circut - valid
    if (SignatureChecker.isValidSignatureNow(req.from, digest, signature)) return;

    SignerEntry memory signer = signerData[req.from][req.to];
    // signer is not set if true:
    require(signer.allowedAddress != address(0), "Forwarder: signature mismatch");
    require(signer.validUntilTime != 0 && signer.validUntilTime > block.timestamp, "Forwarder: signer is no longer approved");
    require(SignatureChecker.isValidSignatureNow(signer.allowedAddress, digest, signature), "Forwarder: signer signature mismatch");
  }

  function _collectFees(address from, address feeToken, uint256 requestValue, uint256 gasUsed, uint256 valueUsed) internal {
    uint256 estimatedFee = estimateFee(feeToken, valueUsed, gasUsed);

    if (feeToken == NativeTokenAddress) {
      if (estimatedFee > requestValue) {
        // if the amount used is greater then the value already collected, collect the difference
        bool success = ERC20(feeToken).transferFrom(from, paymentAddress, estimatedFee - requestValue);
        require(success, 'Forwarder: failed to collect fee');
      } else if (estimatedFee < requestValue) {
        // if the amount used is less then the value already collected, refund the difference
        IWrapper(NativeTokenAddress).deposit{ value: requestValue - estimatedFee}();
        bool success = ERC20(feeToken).transfer(from, requestValue - estimatedFee);      
        require(success, 'Forwarder: failed to refund fee');
      }
    } else {
      bool success = ERC20(feeToken).transferFrom(from, paymentAddress, estimatedFee);
      require(success, 'Forwarder: failed to collect fee');
    }

    emit Fees_Collected(feeToken, from, paymentAddress, estimatedFee, gasUsed);
  }

  function _getTokenAmount(address tokenAddress, uint256 weiConsumed) internal view returns (uint256) {
    weiConsumed = (weiConsumed * (feeNumeratorValue + feeDenominator)) / feeDenominator;
    uint8 decimals = ERC20(tokenAddress).decimals();
    uint256 nativeToken = _getTokenPrice(address(0));
    if (feeTokenData[tokenAddress].isStable) {
      return (weiConsumed * nativeToken) / 10 ** (36 - decimals);
    } else {
      uint256 quotePrice = _getTokenPrice(tokenAddress);
      return ((weiConsumed * nativeToken) / quotePrice) / 10 ** uint256(18 - decimals);
    }
  }

  function _getTokenPrice(address tokenAddress) internal view returns (uint256) {
    (, int256 price, , , ) = feeTokenData[tokenAddress].chainlinkFeed.latestRoundData();
    uint8 priceFeedDecimals = feeTokenData[tokenAddress].chainlinkFeed.decimals();
    return uint256(price) * 10 ** uint256(18 - priceFeedDecimals);
  }
}

